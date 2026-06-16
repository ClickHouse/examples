#!/usr/bin/env python3
"""chDB equivalent of the NDJSON -> CSV conversion (Surface B).

Same SQL as run.sh, run in-process with chDB. Run ./generate.sh first.
"""
import chdb

# The naive SELECT * splits the nested 'device' Tuple into extra columns
# without extra headers. Project the nested fields out explicitly instead,
# and serialise the array as a JSON string so it stays in one CSV cell.
sql = """
SELECT
  event_id,
  ts,
  country,
  action,
  amount,
  device.os          AS device_os,
  device.app_version AS device_version,
  toJSONString(tags) AS tags
FROM file('data/events.ndjson')
INTO OUTFILE 'data/events_flat_chdb.csv' TRUNCATE FORMAT CSVWithNames
"""
chdb.query(sql)
print("wrote data/events_flat_chdb.csv")

# Read the result back as a DataFrame to confirm it is clean tabular data.
df = chdb.query(
    "SELECT * FROM file('data/events_flat_chdb.csv') ORDER BY event_id LIMIT 3",
    "DataFrame",
)
print(df)
