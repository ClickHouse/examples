#!/usr/bin/env python3
"""chDB equivalent of the Parquet -> TSV conversion.

Same SQL as run.sh, in-process in Python. Run ./generate.sh first.
Requires: pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert Parquet -> TSV. chDB streams the SELECT straight into a TSV file.
chdb.query(
    "SELECT * FROM file('events.parquet') "
    "INTO OUTFILE 'events_chdb.tsv' TRUNCATE FORMAT TSVWithNames"
)
print("== wrote events_chdb.tsv ==")
with open("events_chdb.tsv") as f:
    for line in list(f)[:4]:
        print(line.rstrip("\n"))

# 2. Read the TSV back into a DataFrame to confirm the round-trip.
print("\n== read it back as a DataFrame ==")
df = chdb.query(
    "SELECT event_id, country, tags FROM file('events_chdb.tsv', 'TSVWithNames') "
    "ORDER BY event_id LIMIT 3",
    "DataFrame",
)
print(df)
