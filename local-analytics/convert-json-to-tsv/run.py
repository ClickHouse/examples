#!/usr/bin/env python3
"""chDB version of the JSON -> TSV conversion from the article.
Same SQL as run.sh, run in-process in Python. Run ./generate.sh first."""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Flatten the nested "user" object into top-level columns, then write TSV.
sql = """
SELECT
  event_id,
  event_type,
  ts,
  user.id   AS user_id,
  user.plan AS user_plan,
  source,
  amount
FROM file('events.jsonl')
INTO OUTFILE 'events_flat_chdb.tsv' TRUNCATE FORMAT TSVWithNames
"""
chdb.query(sql)

print(open("events_flat_chdb.tsv").read())
