#!/usr/bin/env python3
"""chDB equivalent of the CLI conversion: flatten nested JSON and write CSV.

Same SELECT as run.sh, run in-process with chDB (no server). Run from the
example folder or anywhere; it resolves paths relative to ./data/.
"""
import os
import chdb

here = os.path.join(os.path.dirname(__file__), "data")
os.chdir(here)

# Flatten the nested 'user' object and the 'amounts' array, then write CSV.
sql = """
SELECT
  event_id,
  event_type,
  ts,
  user.country AS user_country,
  user.plan    AS user_plan,
  amounts[1]   AS amount_primary,
  arrayStringConcat(arrayMap(x -> toString(x), amounts), ';') AS amounts_list
FROM file('events.jsonl', JSONEachRow)
INTO OUTFILE 'events_chdb.csv' TRUNCATE
FORMAT CSVWithNames
"""
chdb.query(sql)

# Show the first few lines of the CSV chDB just wrote.
with open("events_chdb.csv") as f:
    for _ in range(5):
        print(f.readline(), end="")
