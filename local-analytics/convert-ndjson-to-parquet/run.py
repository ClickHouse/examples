#!/usr/bin/env python3
"""Convert NDJSON to Parquet in Python with chDB — the same SQL as run.sh,
in-process, no server. Run ./generate.sh first to create ./data/events.ndjson.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert NDJSON -> Parquet with one SELECT ... INTO OUTFILE.
chdb.query(
    "SELECT * FROM file('events.ndjson') "
    "INTO OUTFILE 'events_py.parquet' TRUNCATE FORMAT Parquet"
)
print("rows in events_py.parquet:",
      chdb.query("SELECT count() FROM file('events_py.parquet')", "CSV").bytes().decode().strip())

# 2. Read the nested columns back as a pandas DataFrame.
df = chdb.query(
    "SELECT event_id, user.country AS country, user.plan AS plan, items "
    "FROM file('events_py.parquet') ORDER BY event_id LIMIT 5",
    "DataFrame",
)
print(df)
