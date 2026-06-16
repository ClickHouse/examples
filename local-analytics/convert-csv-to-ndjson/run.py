#!/usr/bin/env python3
"""chDB equivalent of the CSV -> NDJSON conversion.

Same SQL as the CLI version: SELECT from the CSV, FORMAT JSONEachRow, write to a
file. chDB is ClickHouse as an in-process Python module, so the SQL is identical.
Run ./generate.sh first to create ./data/events.csv.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))

# Convert: read the CSV, render every row as a JSON object, write NDJSON.
ndjson = chdb.query(
    "SELECT * FROM file('events.csv') FORMAT JSONEachRow"
).bytes()

with open("events_chdb.ndjson", "wb") as f:
    f.write(ndjson)

print("wrote events_chdb.ndjson")
print()

# Show the first few lines.
with open("events_chdb.ndjson") as f:
    for _ in range(5):
        print(f.readline().rstrip())

print()
# Read the NDJSON straight back to prove the round-trip.
print(
    chdb.query(
        "SELECT country, count() AS events, round(sum(value),2) AS total "
        "FROM file('events_chdb.ndjson') GROUP BY country ORDER BY total DESC"
    )
)
