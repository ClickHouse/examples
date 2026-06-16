#!/usr/bin/env python3
"""chDB equivalent of the CLI conversion: read BSON, flatten the nested
sub-document, write CSV. Same ClickHouse SQL, in-process in Python.
Run ./generate.sh first to create ./data/events.bson."""
import os
import chdb

# Resolve paths relative to this script's data/ folder so it runs from anywhere.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
src = os.path.join(DATA, "events.bson")
out = os.path.join(DATA, "events_flat_chdb.csv")

sql = f"""
SELECT
    event_id,
    event_type,
    geo['city']    AS city,
    geo['country'] AS country,
    amount
FROM file('{src}')
INTO OUTFILE '{out}' TRUNCATE FORMAT CSVWithNames
"""

chdb.query(sql)

print(f"wrote {out}")
print(open(out).read().rstrip())
