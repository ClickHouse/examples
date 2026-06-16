#!/usr/bin/env python3
"""chDB equivalent of the JSONL -> JSON conversion in the article.

Same ClickHouse SQL, run in-process with chdb. No server, no upload.
Run ./generate.sh first to create ./data/events.jsonl.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert JSONL -> a single JSON array, written to a file by ClickHouse itself.
chdb.query("""
SELECT * FROM file('events.jsonl')
INTO OUTFILE 'events_array_py.json' TRUNCATE
FORMAT JSONEachRow SETTINGS output_format_json_array_of_rows = 1
""")

print("== wrote events_array_py.json ==")
with open("events_array_py.json") as f:
    print(f.read())

# Read it back to prove it round-trips (JSONEachRow reads a top-level array).
print("== read back: count + total amount ==")
print(chdb.query(
    "SELECT count() AS rows, round(sum(amount), 2) AS total "
    "FROM file('events_array_py.json', 'JSONEachRow')",
    "CSV"), end="")
