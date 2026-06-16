#!/usr/bin/env python3
"""chDB equivalent of the CSV -> TSV conversion.

Same SQL as the clickhouse-local one-liner: SELECT from the CSV, write the
result INTO OUTFILE as TSVWithNames. In-process, no server, no import step.
Run from the data/ directory (run.sh calls it from there).
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# CSV -> TSV, header kept (TSVWithNames). TRUNCATE makes it idempotent.
chdb.query(
    "SELECT * FROM file('orders.csv') "
    "INTO OUTFILE 'orders_chdb.tsv' TRUNCATE FORMAT TSVWithNames"
)

# Read the first rows back to prove it worked.
df = chdb.query("SELECT * FROM file('orders_chdb.tsv', 'TSVWithNames') LIMIT 3", "DataFrame")
print(df.to_string(index=False))
