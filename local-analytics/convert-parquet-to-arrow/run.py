#!/usr/bin/env python3
"""chDB equivalent of the Parquet -> Arrow conversion.

Same ClickHouse SQL as run.sh, in-process via chDB. Run ./generate.sh first.
Requires: pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert Parquet -> Arrow IPC. Same SELECT ... FORMAT Arrow, written to a file.
arrow_bytes = chdb.query(
    "SELECT * FROM file('events.parquet') FORMAT Arrow"
).bytes()
with open("events_chdb.arrow", "wb") as f:
    f.write(arrow_bytes)
print(f"wrote events_chdb.arrow ({len(arrow_bytes)} bytes)")

# Read it back and confirm the schema + row count survived the round trip.
print("\nschema of the Arrow file:")
print(chdb.query("DESCRIBE file('events_chdb.arrow')", "CSV"))

print("first 5 rows:")
print(chdb.query("SELECT * FROM file('events_chdb.arrow') LIMIT 5", "CSV"))

# Arrow is the native handoff to pandas/pyarrow: no copy, no parse.
df = chdb.query("SELECT * FROM file('events_chdb.arrow')", "DataFrame")
print(f"loaded into a pandas DataFrame: {df.shape[0]} rows x {df.shape[1]} cols")
print(df.dtypes)
