#!/usr/bin/env python3
"""Print a JDBC endpoint without properties; passwords stay in separate variables."""
import os, re
from urllib.parse import quote
host = os.environ["PGHOST"]
port = int(os.environ.get("PGPORT", "5432"))
database = os.environ.get("PGDATABASE", "postgres")
if not re.fullmatch(r"[A-Za-z0-9.-]+", host) or not 1 <= port <= 65535 or not database:
    raise SystemExit("Invalid endpoint fields")
print(f"jdbc:postgresql://{host}:{port}/{quote(database, safe='')}")
