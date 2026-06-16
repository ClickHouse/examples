#!/usr/bin/env python3
"""chDB equivalent of the Avro -> CSV conversion in the article.
Run ./generate.sh first to create ./data/events.avro.
Same SQL as the CLI: SELECT ... FROM file('events.avro') ... FORMAT CSVWithNames."""
import chdb

# Flatten the nested Avro (Tuple -> columns, Array -> joined string, int ts -> DateTime)
# and write a clean, aligned CSV. INTO OUTFILE writes the file from inside the query.
chdb.query("""
SELECT
  event_id,
  toDateTime(ts)               AS ts,
  event_type,
  country,
  amount,
  user_info.1                  AS user_id,
  user_info.2                  AS sessions,
  arrayStringConcat(tags, '|') AS tags
FROM file('data/events.avro')
INTO OUTFILE 'data/events_flat_chdb.csv' TRUNCATE FORMAT CSVWithNames
""")

with open("data/events_flat_chdb.csv") as f:
    print("".join(f.readlines()[:7]), end="")
