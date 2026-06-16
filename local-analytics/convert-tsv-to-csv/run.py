#!/usr/bin/env python3
"""chDB equivalent of the TSV -> CSV conversion from the article.

Same ClickHouse SQL, in-process in Python. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert TSV -> CSV with a header, writing the file directly from SQL.
chdb.query(
    "SELECT * FROM file('events.tsv') "
    "INTO OUTFILE 'events_chdb.csv' TRUNCATE FORMAT CSVWithNames"
)
print("wrote events_chdb.csv")

# Read the first few lines back to prove it worked.
with open("events_chdb.csv") as f:
    for line in list(f)[:6]:
        print(line.rstrip())
