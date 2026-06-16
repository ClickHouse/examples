#!/usr/bin/env python3
"""chDB equivalent of the CSV -> JSON conversion from the article.
Same SELECT ... FORMAT, written to a file from Python. Run ./generate.sh first.
Requires: pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. CSV -> JSON, one object per line (JSONEachRow / NDJSON).
chdb.query(
    "SELECT * FROM file('orders.csv') "
    "INTO OUTFILE 'orders_chdb.jsonl' TRUNCATE FORMAT JSONEachRow"
)
print("== orders_chdb.jsonl (first 3 lines) ==")
with open("orders_chdb.jsonl") as f:
    for _ in range(3):
        print(f.readline().rstrip())

# 2. CSV -> a single JSON array of objects (FORMAT JSON), captured as a string.
print("\n== first 2 rows as a single JSON document (FORMAT JSON) ==")
print(chdb.query("SELECT * FROM file('orders.csv') LIMIT 2 FORMAT JSON"), end="")
