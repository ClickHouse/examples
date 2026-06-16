#!/usr/bin/env python3
"""chDB equivalent of the TSV -> Parquet conversion (Surface B, in-process Python).

Same ClickHouse SQL as run.sh, run in-process with chdb. No server, no import step.
Run ./generate.sh first to create ./data/events.tsv.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))

# Convert TSV -> Parquet with one SELECT ... INTO OUTFILE. Types are inferred
# from the TSV and carried into the Parquet schema; ClickHouse compresses with
# zstd by default.
chdb.query("""
SELECT * FROM file('events.tsv')
INTO OUTFILE 'events_chdb.parquet' TRUNCATE
FORMAT Parquet
""")

# Confirm the inferred schema landed in the Parquet file.
print(chdb.query("DESCRIBE file('events_chdb.parquet')", "TSV"))

# Read it back to prove the round-trip is correct.
print(chdb.query(
    "SELECT * FROM file('events_chdb.parquet') ORDER BY event_id LIMIT 5", "CSV"))
