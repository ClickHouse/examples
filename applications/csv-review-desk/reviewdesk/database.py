import os
from pathlib import Path

from sqlalchemy import URL, create_engine


def make_engine():
    ca = Path(os.environ["PGSSLROOTCERT"])
    if not ca.is_file():
        raise ValueError("PGSSLROOTCERT must point to the downloaded Cloud CA")
    url = URL.create(
        "postgresql+psycopg",
        username=os.environ["PGUSER"],
        password=os.environ["PGPASSWORD"],
        host=os.environ["PGHOST"],
        port=int(os.environ.get("PGPORT", "5432")),
        database=os.environ.get("PGDATABASE", "postgres"),
    )
    return create_engine(
        url,
        pool_size=4,
        max_overflow=0,
        pool_pre_ping=True,
        connect_args={
            "sslmode": "verify-full",
            "sslrootcert": str(ca.resolve()),
            "connect_timeout": 10,
            "options": "-c search_path=csv_review,public -c statement_timeout=15000 -c lock_timeout=10000",
        },
        hide_parameters=True,
    )
