import os
from pathlib import Path

from pgvector.psycopg import register_vector
from sqlalchemy import URL, event
from sqlmodel import create_engine


def make_engine():
    for key in ["PGHOST", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLROOTCERT"]:
        if not os.getenv(key):
            raise ValueError(f"{key} is required.")
    certificate = Path(os.environ["PGSSLROOTCERT"])
    if not certificate.is_file():
        raise ValueError("The Cloud CA file must exist.")
    url = URL.create(
        "postgresql+psycopg",
        username=os.environ["PGUSER"],
        password=os.environ["PGPASSWORD"],
        host=os.environ["PGHOST"],
        port=int(os.getenv("PGPORT", "5432")),
        database=os.environ["PGDATABASE"],
    )
    engine = create_engine(
        url,
        pool_size=4,
        max_overflow=0,
        pool_timeout=5,
        pool_pre_ping=True,
        connect_args={
            "sslmode": "verify-full",
            "sslrootcert": str(certificate),
            "connect_timeout": 10,
            "options": "-csearch_path=semantic_notes,public -cstatement_timeout=15000",
            "application_name": "semantic-notes",
        },
    )

    @event.listens_for(engine, "connect")
    def register(dbapi_connection, _connection_record):
        register_vector(dbapi_connection)

    return engine
