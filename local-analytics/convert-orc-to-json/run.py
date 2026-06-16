#!/usr/bin/env python3
"""chDB equivalent of the ORC -> JSON conversion in the article.

Same SQL as run.sh, in-process in Python. Run ./generate.sh first.
Requires: chdb (pip install chdb).
"""
import chdb

# Convert ORC -> NDJSON: same SELECT ... FORMAT, written to a file.
sql = """
SELECT * FROM file('data/events.orc')
INTO OUTFILE 'data/events_chdb.jsonl' TRUNCATE
FORMAT JSONEachRow
"""
chdb.query(sql)

with open("data/events_chdb.jsonl") as f:
    for line in list(f)[:3]:
        print(line.rstrip())
