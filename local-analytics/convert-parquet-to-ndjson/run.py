#!/usr/bin/env python3
"""chDB version of the Parquet -> NDJSON conversion.

The SQL is identical to the clickhouse-local one-liner; chDB runs the same
ClickHouse engine in-process, so INTO OUTFILE ... FORMAT JSONEachRow works the
same way. Run ./generate.sh first to create ./data/events.parquet.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert Parquet -> NDJSON with the same SELECT ... INTO OUTFILE ... FORMAT.
chdb.query(
    "SELECT * FROM file('events.parquet') "
    "INTO OUTFILE 'events_py.ndjson' TRUNCATE FORMAT JSONEachRow"
)
print("first 3 lines of events_py.ndjson:")
with open("events_py.ndjson") as f:
    for _, line in zip(range(3), f):
        print(line.rstrip())

# 2. Or capture the NDJSON as a string instead of a file.
ndjson = chdb.query(
    "SELECT event_id, country, amount FROM file('events.parquet') "
    "WHERE action = 'purchase' ORDER BY amount DESC LIMIT 2 FORMAT JSONEachRow"
)
print("\ntop purchases as an NDJSON string:")
print(str(ndjson).rstrip())
