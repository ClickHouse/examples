#!/usr/bin/env python3
"""chDB equivalent of run.sh: convert a TSV file to JSON in-process, no server.

Run ./generate.sh first to create ./data/events.tsv.
Requires: pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert TSV -> JSON (JSONEachRow = one object per line / NDJSON).
#    chdb.query returns the JSONEachRow text; write it to a file.
ndjson = chdb.query("SELECT * FROM file('events.tsv') LIMIT 3", "JSONEachRow")
print("== 1. TSV -> JSONEachRow (NDJSON) ==")
print(str(ndjson).strip())

# Write the full file out.
with open("events_chdb.jsonl", "w") as f:
    f.write(str(chdb.query("SELECT * FROM file('events.tsv')", "JSONEachRow")))

# 2. Convert TSV -> a single JSON array.
arr = chdb.query(
    "SELECT * FROM file('events.tsv') LIMIT 3 "
    "SETTINGS output_format_json_array_of_rows = 1",
    "JSONEachRow",
)
print("\n== 2. TSV -> single JSON array ==")
print(str(arr).strip())
with open("events_chdb.json", "w") as f:
    f.write(str(chdb.query(
        "SELECT * FROM file('events.tsv') "
        "SETTINGS output_format_json_array_of_rows = 1",
        "JSONEachRow",
    )))

# 3. Transform on the way out, then write.
print("\n== 3. Transform (filter + rename) -> JSON ==")
print(str(chdb.query(
    "SELECT event_date, country, upper(action) AS action_upper, value "
    "FROM file('events.tsv') WHERE action = 'purchase' "
    "ORDER BY value DESC LIMIT 3",
    "JSONEachRow",
)).strip())
