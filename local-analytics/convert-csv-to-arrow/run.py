#!/usr/bin/env python3
"""chDB equivalent of the CSV -> Arrow conversion (Surface B).

Same SELECT ... INTO OUTFILE ... FORMAT Arrow as `clickhouse local`, run
in-process from Python with chdb. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert CSV -> Arrow in one line (same SQL as the CLI).
chdb.query("SELECT * FROM file('events.csv') INTO OUTFILE 'events_py.arrow' TRUNCATE FORMAT Arrow")
print("written events_py.arrow")

# 2. Prove it: row count + the types embedded in the Arrow schema.
print("rows:", chdb.query("SELECT count() FROM file('events_py.arrow')", "CSV"), end="")
print(chdb.query("DESCRIBE file('events_py.arrow')", "TabSeparated"), end="")

# 3. Query the Arrow file straight back as a DataFrame, no re-parse.
df = chdb.query(
    "SELECT country, count() AS events, round(sum(amount),2) AS amount "
    "FROM file('events_py.arrow') GROUP BY country ORDER BY amount DESC LIMIT 5",
    "DataFrame",
)
print(df.to_string(index=False))
