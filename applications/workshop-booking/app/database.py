"""One bounded SQLAlchemy connection pool per application process."""

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import URL, Engine, create_engine
from sqlalchemy.orm import Session

from app.config import Settings


def build_engine(settings: Settings) -> Engine:
    # URL.create keeps special characters in passwords out of URI parsing.
    url = URL.create(
        "postgresql+psycopg",
        username=settings.user,
        password=settings.password,
        host=settings.host,
        port=settings.port,
        database=settings.database,
    )
    return create_engine(
        url,
        connect_args={
            "sslmode": "verify-full",
            "sslrootcert": str(settings.sslrootcert),
            "connect_timeout": 10,
            "application_name": "workshop-booking",
            "options": (
                "-c statement_timeout=5000 -c lock_timeout=3000 "
                "-c idle_in_transaction_session_timeout=10000"
            ),
        },
        pool_size=5,
        max_overflow=5,
        pool_timeout=5,
        pool_pre_ping=True,
        pool_recycle=300,
        isolation_level="READ COMMITTED",
        hide_parameters=True,
    )


def get_session(request: Request) -> Iterator[Session]:
    # Routes own the transaction so commit finishes before a success is returned.
    with request.app.state.session_factory() as session:
        yield session
