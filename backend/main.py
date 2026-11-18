import hashlib
import os
import secrets
import time
from typing import Annotated
from uuid import uuid4

import httpx
import jwt
from cryptography.fernet import Fernet, MultiFernet
from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DatabaseSession

from models import Challenge, Connection, Session


class Nonce(BaseModel):
    nonce: str


class AppleLogin(Nonce):
    identity_token: str = Field(max_length=16000)


class SessionToken(BaseModel):
    token: str


class LinkToken(BaseModel):
    link_token: str


class Exchange(BaseModel):
    public_token: str = Field(min_length=1, max_length=512)
    name: str = Field(default="Credit card", max_length=120)


class ConnectionInfo(BaseModel):
    id: str
    name: str


class SyncCursor(BaseModel):
    cursor: str | None = Field(default=None, max_length=4096)


class Charge(BaseModel):
    id: str
    day: str
    name: str
    category: str
    amount: float
    pending: bool
    excluded: bool
    pendingID: str | None


class SyncResult(BaseModel):
    cursor: str
    changes: list[Charge]
    removed: list[str]


CATEGORIES = {
    "FOOD_AND_DRINK": "Food",
    "GENERAL_MERCHANDISE": "Goods",
    "ENTERTAINMENT": "Entertainment",
    "TRANSPORTATION": "Transport",
    "MEDICAL": "Medical",
    "TRAVEL": "Travel",
    "RENT_AND_UTILITIES": "Utilities",
    "HOME_IMPROVEMENT": "Housing",
}


def charge(row):
    classification = row.get("personal_finance_category") or {}
    primary = classification.get("primary")
    detailed = classification.get("detailed", "")
    excluded = (
        primary in {"TRANSFER_IN", "TRANSFER_OUT", "INCOME"}
        or detailed == "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"
        or row.get("iso_currency_code", "USD") != "USD"
    )
    return Charge(
        id=row["transaction_id"], day=row["date"], name=row.get("merchant_name") or row["name"],
        category=CATEGORIES.get(primary, "Miscellaneous"), amount=row["amount"],
        pending=row["pending"], excluded=excluded, pendingID=row.get("pending_transaction_id"),
    )


class PlaidError(Exception):
    def __init__(self, code):
        self.code = code


def transactions(plaid, token, cursor):
    # Restart from the original cursor when Plaid invalidates pagination.
    for _ in range(3):
        current = cursor
        changes = {}
        removed = set()
        try:
            for _ in range(200):
                page = plaid("/transactions/sync", access_token=token, cursor=current or "", count=500)
                credit = {row["account_id"] for row in page["accounts"] if row["type"] == "credit" and row.get("subtype") == "credit card"}
                for row in page["added"] + page["modified"]:
                    key = row["transaction_id"]
                    if row["account_id"] in credit:
                        changes[key] = charge(row)
                        removed.discard(key)
                    else:
                        changes.pop(key, None)
                        removed.add(key)
                for row in page["removed"]:
                    key = row["transaction_id"]
                    changes.pop(key, None)
                    removed.add(key)
                current = page["next_cursor"]
                if not page["has_more"]:
                    return SyncResult(cursor=current, changes=list(changes.values()), removed=sorted(removed))
        except PlaidError as error:
            if error.code != "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION":
                raise
    raise HTTPException(503, "Transaction pagination did not complete. Retry sync.")


def apple_verifier(audience, keys=None):
    if keys is None:
        keys = jwt.PyJWKClient("https://appleid.apple.com/auth/keys", timeout=8)

    def verify(token):
        key = keys.get_signing_key_from_jwt(token).key
        return jwt.decode(token, key, algorithms=["RS256"], issuer="https://appleid.apple.com",
                          audience=audience, options={"require": ["exp", "iat", "sub", "nonce"]})

    return verify


def create_app(engine=None, verify_apple=None, plaid=None, cipher=None):
    app = FastAPI(title="Trajectory Card Imports", version="1.0.0")
    bearer = HTTPBearer(auto_error=False)
    engine = engine if engine is not None else create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)
    if cipher is None:
        cipher = MultiFernet([Fernet(key.encode()) for key in os.environ["PLAID_TOKEN_KEYS"].split(",")])

    if verify_apple is None:
        verify_apple = apple_verifier(os.environ["APPLE_CLIENT_ID"])

    if plaid is None:
        environment = os.getenv("PLAID_ENV", "sandbox")
        if environment not in {"sandbox", "production"}:
            raise ValueError("PLAID_ENV must be sandbox or production")
        credentials = {"client_id": os.environ["PLAID_CLIENT_ID"], "secret": os.environ["PLAID_SECRET"]}

        def plaid(path, **payload):
            try:
                response = httpx.post(f"https://{environment}.plaid.com{path}", json=credentials | payload,
                                      headers={"Plaid-Version": "2020-09-14"}, timeout=20)
                result = response.json()
            except (httpx.HTTPError, ValueError):
                raise PlaidError("PLAID_UNAVAILABLE") from None
            if not response.is_success:
                raise PlaidError(result.get("error_code", "PLAID_UNAVAILABLE"))
            return result

    @app.exception_handler(PlaidError)
    def plaid_error(_request, error):
        from fastapi.responses import JSONResponse
        needs_login = error.code == "ITEM_LOGIN_REQUIRED"
        message = "Reconnect this card in Accounts & Data." if needs_login else "Plaid could not complete the request."
        return JSONResponse(status_code=409 if needs_login else 502, content={"detail": message})

    def database():
        with DatabaseSession(engine) as db:
            yield db

    def authorized(
        db: Annotated[DatabaseSession, Depends(database)],
        auth: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ):
        digest = hashlib.sha256(auth.credentials.encode()).hexdigest() if auth else ""
        session = db.get(Session, digest)
        if session is None or session.expires <= time.time():
            raise HTTPException(401, "Sign in with Apple to continue.")
        return session

    def owned(db, session, id, lock=False):
        query = select(Connection).where(Connection.id == id, Connection.owner == session.owner)
        connection = db.scalar(query.with_for_update() if lock else query)
        if connection is None:
            raise HTTPException(404, "Connection not found.")
        return connection

    def link(owner, access_token=None):
        request = {
            "client_name": "Trajectory", "language": "en", "country_codes": ["US"],
            "user": {"client_user_id": hashlib.sha256(owner.encode()).hexdigest()},
        }
        redirect = os.getenv("PLAID_REDIRECT_URI")
        if redirect:
            request["redirect_uri"] = redirect
        if access_token:
            request["access_token"] = access_token
        else:
            request.update(products=["transactions"], account_filters={"credit": {"account_subtypes": ["credit card"]}})
        return LinkToken(link_token=plaid("/link/token/create", **request)["link_token"])

    @app.post("/auth/nonce", response_model=Nonce)
    def nonce(db: Annotated[DatabaseSession, Depends(database)]):
        value = secrets.token_urlsafe(32)
        now = int(time.time())
        db.execute(delete(Challenge).where(Challenge.expires <= now))
        db.add(Challenge(nonce=value, expires=now + 300))
        db.commit()
        return Nonce(nonce=value)

    @app.post("/auth/apple", response_model=SessionToken)
    def authenticate(body: AppleLogin, db: Annotated[DatabaseSession, Depends(database)]):
        try:
            claims = verify_apple(body.identity_token)
        except jwt.PyJWKClientConnectionError:
            raise HTTPException(503, "Apple verification is unavailable.") from None
        except jwt.PyJWTError:
            raise HTTPException(401, "Apple authorization could not be verified.") from None
        if claims.get("nonce") != body.nonce or not claims.get("sub"):
            raise HTTPException(401, "Apple authorization did not match the challenge.")
        used = db.execute(delete(Challenge).where(Challenge.nonce == body.nonce, Challenge.expires > int(time.time())))
        if used.rowcount != 1:
            raise HTTPException(401, "Apple authorization challenge has expired or was already used.")
        token = secrets.token_urlsafe(32)
        db.add(Session(digest=hashlib.sha256(token.encode()).hexdigest(), owner=claims["sub"],
                       expires=int(time.time()) + 30 * 86400))
        db.commit()
        return SessionToken(token=token)

    @app.delete("/auth/session", status_code=204)
    def logout(db: Annotated[DatabaseSession, Depends(database)], session: Annotated[Session, Depends(authorized)]):
        db.delete(session)
        db.commit()
        return Response(status_code=204)

    @app.post("/connections/link-token", response_model=LinkToken)
    def link_token(session: Annotated[Session, Depends(authorized)]):
        return link(session.owner)

    @app.post("/connections/exchange", response_model=ConnectionInfo, status_code=201)
    def exchange(body: Exchange, db: Annotated[DatabaseSession, Depends(database)],
                 session: Annotated[Session, Depends(authorized)]):
        result = plaid("/item/public_token/exchange", public_token=body.public_token)
        if db.scalar(select(Connection.id).where(Connection.item == result["item_id"])):
            raise HTTPException(409, "This Plaid connection already exists.")
        connection = Connection(id=str(uuid4()), item=result["item_id"], owner=session.owner,
                                token=cipher.encrypt(result["access_token"].encode()), name=body.name)
        db.add(connection)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "This Plaid connection already exists.") from None
        return ConnectionInfo(id=connection.id, name=connection.name)

    @app.get("/connections", response_model=list[ConnectionInfo])
    def connections(db: Annotated[DatabaseSession, Depends(database)], session: Annotated[Session, Depends(authorized)]):
        rows = db.scalars(select(Connection).where(Connection.owner == session.owner).order_by(Connection.name, Connection.id))
        return [ConnectionInfo(id=row.id, name=row.name) for row in rows]

    @app.post("/connections/{id}/sync", response_model=SyncResult)
    def sync(id: str, body: SyncCursor, db: Annotated[DatabaseSession, Depends(database)],
             session: Annotated[Session, Depends(authorized)]):
        connection = owned(db, session, id)
        return transactions(plaid, cipher.decrypt(connection.token).decode(), body.cursor)

    @app.post("/connections/{id}/reconnect", response_model=LinkToken)
    def reconnect(id: str, db: Annotated[DatabaseSession, Depends(database)], session: Annotated[Session, Depends(authorized)]):
        connection = owned(db, session, id)
        return link(session.owner, cipher.decrypt(connection.token).decode())

    @app.delete("/connections/{id}", status_code=204)
    def disconnect(id: str, db: Annotated[DatabaseSession, Depends(database)], session: Annotated[Session, Depends(authorized)]):
        connection = owned(db, session, id, lock=True)
        try:
            plaid("/item/remove", access_token=cipher.decrypt(connection.token).decode())
        except PlaidError as error:
            if error.code != "ITEM_NOT_FOUND":
                raise
        db.delete(connection)
        db.commit()
        return Response(status_code=204)

    return app
