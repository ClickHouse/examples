#!/usr/bin/env python3
"""chDB equivalent of run.sh: convert Avro -> Parquet in-process, no server.
Run ./generate.sh first to create ./data/events.avro.
Requires: pip install chdb
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert Avro -> Parquet. Same SELECT ... INTO OUTFILE ... FORMAT as the CLI,
# run inside Python. chDB embeds the ClickHouse engine, so there is no server.
chdb.query("""
SELECT * FROM file('events.avro')
INTO OUTFILE 'events_py.parquet' TRUNCATE FORMAT Parquet
""")
print("wrote events_py.parquet")

# The schema Avro carried, now in the Parquet file.
print(chdb.query("DESCRIBE file('events_py.parquet')", "CSV"))

# Read it back into a pandas DataFrame to confirm the round-trip.
df = chdb.query("SELECT * FROM file('events_py.parquet') ORDER BY event_id LIMIT 5", "DataFrame")
print(df)
