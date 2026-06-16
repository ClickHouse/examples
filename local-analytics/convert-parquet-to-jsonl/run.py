#!/usr/bin/env python3
"""chDB equivalent of the Parquet -> JSONL conversion (Surface B).

Same ClickHouse SQL, in-process in Python: no server, no copy step.
Run ./generate.sh first to create ./data/events.parquet.
"""
import chdb

# Convert Parquet -> JSONL straight to a file. Same SELECT ... FORMAT JSONEachRow
# as the CLI; INTO OUTFILE writes the file from inside the Python process.
chdb.query(
    "SELECT * FROM file('data/events.parquet') "
    "INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow"
)

# Show the proof: first three lines, one JSON object each.
with open("data/events.jsonl") as f:
    lines = f.read().splitlines()
print("first 3 lines:")
for line in lines[:3]:
    print(line)
print("total lines:", len([l for l in lines if l]))
