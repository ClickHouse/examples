#!/usr/bin/env python3
"""Convert Parquet to Avro with chDB (in-process ClickHouse, no server).

Mirrors run.ipynb and the chDB block in the companion article.
Run ./generate.sh first to create the sample Parquet files in ./data/.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert Parquet -> Avro: the same SELECT ... FORMAT Avro, into a file.
chdb.query(
    "SELECT * FROM file('events.parquet') "
    "INTO OUTFILE 'events.avro' TRUNCATE FORMAT Avro"
)
print("converted events.parquet -> events.avro")

# 2. Read the Avro back and confirm the row count.
print(chdb.query("SELECT count() AS rows FROM file('events.avro')", "DataFrame"))

# 3. The nested tuple round-trips as a nested Avro record.
print(
    chdb.query(
        "SELECT event_id, country, device.1 AS device_type, device.2 AS is_even "
        "FROM file('events.avro') ORDER BY event_id LIMIT 3",
        "PrettyCompact",
    )
)
