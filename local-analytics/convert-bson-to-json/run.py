#!/usr/bin/env python3
"""chDB equivalent of the BSON -> JSON conversion in the article.

Same SQL as run.sh, run in-process with chDB (no server, no clickhouse binary).
Run ./generate.sh first to create ./data/users.bson and ./data/events.bson.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert BSON -> NDJSON. The SELECT ... INTO OUTFILE ... FORMAT is identical
#    to the CLI; chDB runs it in this Python process.
chdb.query(
    "SELECT * FROM file('users.bson') "
    "INTO OUTFILE 'users_chdb.jsonl' TRUNCATE FORMAT JSONEachRow"
)
print("== BSON -> NDJSON (users_chdb.jsonl) ==")
print(open("users_chdb.jsonl").read().rstrip())

# 2. Same schema inference as the CLI.
print("\n== Inferred schema ==")
print(chdb.query("DESCRIBE file('users.bson')", "CSV").bytes().decode().rstrip())

# 3. Filter + flatten while converting.
chdb.query(
    "SELECT _id, name, address['zip'] AS zip, tags "
    "FROM file('users.bson') WHERE active "
    "INTO OUTFILE 'active_chdb.jsonl' TRUNCATE FORMAT JSONEachRow"
)
print("\n== Active users only, zip flattened (active_chdb.jsonl) ==")
print(open("active_chdb.jsonl").read().rstrip())
