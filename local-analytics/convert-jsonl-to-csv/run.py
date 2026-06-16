#!/usr/bin/env python3
"""chDB equivalent of the article "How to convert JSONL to CSV".
Run ./generate.sh first to create ./data/events.jsonl.
chDB is the in-process ClickHouse engine for Python: same SQL, no server."""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Flatten the nested geo object and the tags array into scalar CSV columns,
# then write straight to a file with the same SELECT ... FORMAT.
sql = """
SELECT
  event_id,
  ts,
  action,
  geo.country AS geo_country,
  geo.city    AS geo_city,
  arrayStringConcat(tags, '|') AS tags
FROM file('events.jsonl')
INTO OUTFILE 'events_chdb.csv' TRUNCATE FORMAT CSVWithNames
"""
chdb.query(sql)

print("== events_chdb.csv ==")
print(open("events_chdb.csv").read())
