#!/usr/bin/env python3
"""chDB version of "How to convert Arrow to CSV".
Same SQL as run.sh, in-process in Python. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert Arrow -> CSV in one line. The schema is read from the Arrow file;
#    no structure has to be supplied.
chdb.query(
    "SELECT * FROM file('events.arrow') "
    "INTO OUTFILE 'events_chdb.csv' TRUNCATE FORMAT CSVWithNames"
)
with open("events_chdb.csv") as f:
    head = f.read().splitlines()
print("== events_chdb.csv (first 4 lines) ==")
print("\n".join(head[:4]))

# 2. The nested Array column flattens to a quoted string in CSV (the gotcha).
print("\n== tags column round-tripped through CSV ==")
print(chdb.query("SELECT event_id, tags FROM file('events_chdb.csv') LIMIT 3", "CSV"), end="")

# 3. Transform during conversion, straight to a DataFrame if you prefer.
print("\n== by_country, as a DataFrame ==")
df = chdb.query(
    "SELECT country, count() AS events, round(sum(amount),2) AS total "
    "FROM file('events.arrow') GROUP BY country ORDER BY total DESC",
    "DataFrame",
)
print(df.to_string(index=False))
