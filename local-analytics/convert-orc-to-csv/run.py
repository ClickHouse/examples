#!/usr/bin/env python3
"""chDB equivalent of the ORC -> CSV conversion.

Same SQL as run.sh, in-process. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert ORC -> CSV, flattening the Map column into scalar columns.
# INTO OUTFILE writes the file from inside chDB; nothing returns to Python.
chdb.query("""
SELECT
  event_time,
  event_id,
  country,
  action,
  amount,
  tags['utm_source'] AS utm_source,
  tags['device']     AS device
FROM file('events.orc')
INTO OUTFILE 'events_chdb.csv' TRUNCATE FORMAT CSVWithNames
""")

# Show the first few lines of the result.
print("first 6 lines of data/events_chdb.csv:")
with open("events_chdb.csv") as f:
    for i, line in enumerate(f):
        if i >= 6:
            break
        print(line.rstrip())
