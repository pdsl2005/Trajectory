from sqlalchemy import BigInteger, LargeBinary, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Session(Base):
    __tablename__ = "sessions"
    digest: Mapped[str] = mapped_column(Text, primary_key=True)
    owner: Mapped[str] = mapped_column(Text, index=True)
    expires: Mapped[int] = mapped_column(BigInteger)


class Challenge(Base):
    __tablename__ = "apple_challenges"
    nonce: Mapped[str] = mapped_column(Text, primary_key=True)
    expires: Mapped[int] = mapped_column(BigInteger, index=True)


class Connection(Base):
    __tablename__ = "connections"
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    item: Mapped[str] = mapped_column(Text, unique=True)
    owner: Mapped[str] = mapped_column(Text, index=True)
    token: Mapped[bytes] = mapped_column(LargeBinary)
    name: Mapped[str] = mapped_column(Text)
