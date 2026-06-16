#!/usr/bin/env python3
"""chDB equivalent of the JSONL -> Parquet conversion from the article.
Same ClickHouse SQL, in-process, no server. Run ./generate.sh first.
"""
import chdb
import os

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert JSONL -> Parquet with the same SELECT ... INTO OUTFILE ... FORMAT.
chdb.query(
    "SELECT * FROM file('events.jsonl') "
    "INTO OUTFILE 'events_chdb.parquet' TRUNCATE FORMAT Parquet"
)
print("wrote events_chdb.parquet")

# 2. Verify: same row count, types carried over, nested object kept as a struct.
print(chdb.query("SELECT count() AS rows FROM file('events_chdb.parquet')", "PrettyCompact"))
print(chdb.query("DESCRIBE file('events_chdb.parquet')", "PrettyCompact"))
print(chdb.query(
    "SELECT event_id, device.os AS os, device.ver AS ver, amount "
    "FROM file('events_chdb.parquet') ORDER BY event_id LIMIT 5",
    "PrettyCompact",
))
