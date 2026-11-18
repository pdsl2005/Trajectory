import time
from types import SimpleNamespace

import jwt
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from main import PlaidError, apple_verifier, create_app
from models import Base, Connection


def setup(plaid):
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    cipher = Fernet(Fernet.generate_key())
    signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    resolver = SimpleNamespace(get_signing_key_from_jwt=lambda _: SimpleNamespace(key=signing_key.public_key()))
    client = TestClient(create_app(engine=engine, cipher=cipher, plaid=plaid,
                                   verify_apple=apple_verifier("com.trajectory.test", keys=resolver)))

    def claims(subject, nonce):
        return {"sub": subject, "nonce": nonce, "exp": time.time() + 60, "iat": time.time() - 1,
                "iss": "https://appleid.apple.com", "aud": "com.trajectory.test"}

    def login(subject):
        nonce = client.post("/auth/nonce").json()["nonce"]
        token = jwt.encode(claims(subject, nonce), signing_key, algorithm="RS256")
        payload = {"nonce": nonce, "identity_token": token}
        signed_for_other_app = jwt.encode(claims(subject, nonce) | {"aud": "example.other"}, signing_key, algorithm="RS256")
        assert client.post("/auth/apple", json=payload | {"identity_token": signed_for_other_app}).status_code == 401
        assert client.post("/auth/apple", json=payload | {"nonce": "wrong-challenge"}).status_code == 401
        response = client.post("/auth/apple", json=payload)
        assert response.status_code == 200, response.text
        assert client.post("/auth/apple", json=payload).status_code == 401
        return {"Authorization": f"Bearer {response.json()['token']}"}

    return client, login, engine, cipher


def test_auth_and_connection_ownership():
    requests = []

    def plaid(path, **payload):
        requests.append((path, payload))
        if path == "/link/token/create":
            return {"link_token": "link-test"}
        if path == "/item/public_token/exchange":
            return {"item_id": "item-test", "access_token": "access-test"}
        if path == "/item/remove":
            return {}
        assert False, path

    client, login, engine, cipher = setup(plaid)
    assert client.get("/connections").status_code == 401
    nonce = client.post("/auth/nonce").json()["nonce"]
    assert client.post("/auth/apple", json={"nonce": nonce, "identity_token": "invalid"}).status_code == 401
    alice = login("alice")
    bob = login("bob")
    assert client.post("/connections/link-token", headers=alice).json() == {"link_token": "link-test"}
    assert requests[-1][1]["account_filters"] == {"credit": {"account_subtypes": ["credit card"]}}
    connection = client.post("/connections/exchange", headers=alice, json={"public_token": "public-test", "name": "Test Card"})
    assert connection.status_code == 201, connection.text
    data = connection.json()
    path = "/connections/" + data["id"]
    with Session(engine) as db:
        row = db.scalar(select(Connection))
        assert row.token != b"access-test"
        assert cipher.decrypt(row.token) == b"access-test"
    assert client.get("/connections", headers=alice).json() == [data]
    assert client.get("/connections", headers=bob).json() == []
    assert client.post(path + "/sync", headers=bob, json={}).status_code == 404
    assert client.post(path + "/reconnect", headers=bob).status_code == 404
    assert client.delete(path, headers=bob).status_code == 404
    assert client.post(path + "/reconnect", headers=alice).json() == {"link_token": "link-test"}
    assert requests[-1][1]["access_token"] == "access-test"
    assert "products" not in requests[-1][1]
    assert client.delete(path, headers=alice).status_code == 204
    assert client.get("/connections", headers=alice).json() == []
    assert client.delete("/auth/session", headers=alice).status_code == 204
    assert client.get("/connections", headers=alice).status_code == 401
    assert client.get("/connections", headers=bob).status_code == 200


def test_sync_restarts_and_replays_without_committing_cursor_on_server():
    cursors = []

    def row(id, amount, category="FOOD_AND_DRINK", detail="", pending=False, previous=None, account="credit"):
        return {"transaction_id": id, "account_id": account, "date": "2027-01-14", "name": id, "amount": amount,
                "pending": pending, "pending_transaction_id": previous,
                "personal_finance_category": {"primary": category, "detailed": detail}}

    def page(next_cursor, added=(), modified=(), removed=(), more=False):
        return {"accounts": [{"account_id": "credit", "type": "credit", "subtype": "credit card"}, {"account_id": "checking", "type": "depository"}],
                "next_cursor": next_cursor, "added": list(added), "modified": list(modified),
                "removed": [{"transaction_id": id} for id in removed], "has_more": more}

    def plaid(path, **payload):
        if path == "/item/public_token/exchange":
            return {"item_id": "item-test", "access_token": "access-test"}
        assert path == "/transactions/sync"
        cursor = payload["cursor"]
        cursors.append(cursor)
        if cursors == [""]:
            return page("abandoned", [row("must-discard", 100)], more=True)
        if cursor == "abandoned":
            raise PlaidError("TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION")
        if cursor == "":
            return page("middle", [row("pending", 20, pending=True), row("checking", 2, account="checking")], more=True)
        if cursor == "middle":
            return page("done", [row("posted", 21, previous="pending"), row("refund", -3),
                                 row("payment", -100, "LOAN_PAYMENTS", "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")],
                        [row("posted", 22, previous="pending")], ["pending"])
        return page("done")

    client, login, _, _ = setup(plaid)
    alice = login("alice")
    id = client.post("/connections/exchange", headers=alice, json={"public_token": "public"}).json()["id"]
    path = f"/connections/{id}/sync"
    first = client.post(path, headers=alice, json={}).json()
    assert cursors == ["", "abandoned", "", "middle"]
    assert first["cursor"] == "done"
    assert set(first["removed"]) == {"pending", "checking"}
    rows = {row["id"]: row for row in first["changes"]}
    assert set(rows) == {"posted", "refund", "payment"}
    assert rows["posted"]["pendingID"] == "pending" and rows["posted"]["amount"] == 22
    assert rows["refund"]["amount"] == -3 and not rows["refund"]["excluded"]
    assert rows["payment"]["excluded"]
    assert client.post(path, headers=alice, json={}).json() == first
    assert client.post(path, headers=alice, json={"cursor": "done"}).json() == {"cursor": "done", "changes": [], "removed": []}
    assert client.get("/openapi.json").json()["components"]["schemas"]["SyncResult"]
