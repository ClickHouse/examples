#!/usr/bin/env python3
"""chDB equivalent of the Arrow IPC -> Parquet conversion.

Same ClickHouse SQL, in-process, no server. Run ./generate.sh first.
    pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert Arrow IPC file -> Parquet with the same SELECT ... INTO OUTFILE.
chdb.query(
    "SELECT * FROM file('events.arrow') "
    "INTO OUTFILE 'events_chdb.parquet' TRUNCATE FORMAT Parquet"
)

# Verify: row count and the types carried into the Parquet file.
print("rows:", chdb.query("SELECT count() FROM file('events_chdb.parquet')", "CSV"), end="")
print("schema:")
print(chdb.query("DESCRIBE file('events_chdb.parquet')", "CSV"), end="")

# Streaming Arrow IPC needs the ArrowStream format named explicitly.
chdb.query(
    "SELECT * FROM file('events_stream.arrow', 'ArrowStream') "
    "INTO OUTFILE 'events_stream_chdb.parquet' TRUNCATE FORMAT Parquet"
)
print("stream rows:", chdb.query("SELECT count() FROM file('events_stream_chdb.parquet')", "CSV"), end="")
