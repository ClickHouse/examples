#!/usr/bin/env python3
"""chDB equivalent of the ORC -> Parquet conversion (Surface B).

Run ./generate.sh first to create ./data/events.orc.
chDB is ClickHouse as an in-process Python engine: the SELECT ... INTO OUTFILE
is identical to the CLI, no server and no upload.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert ORC -> Parquet with the same SELECT ... INTO OUTFILE the CLI uses.
chdb.query(
    "SELECT * FROM file('events.orc') "
    "INTO OUTFILE 'events_from_py.parquet' TRUNCATE FORMAT Parquet"
)
print("written events_from_py.parquet")

# Verify: row count and a few rows read back from the Parquet file.
print(chdb.query("SELECT count() FROM file('events_from_py.parquet')", "CSV"), end="")
print(
    chdb.query(
        "SELECT event_id, country, event_type, amount, attrs "
        "FROM file('events_from_py.parquet') ORDER BY event_id LIMIT 3",
        "PrettyCompact",
    ),
    end="",
)

# Choose the Parquet compression codec from Python, same setting as the CLI.
chdb.query(
    "SELECT * FROM file('events.orc') "
    "INTO OUTFILE 'events_from_py_zstd.parquet' TRUNCATE FORMAT Parquet "
    "SETTINGS output_format_parquet_compression_method='zstd'"
)
print("written events_from_py_zstd.parquet")
