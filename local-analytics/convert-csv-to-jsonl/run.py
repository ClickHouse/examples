#!/usr/bin/env python3
"""chDB equivalent of the CSV -> JSONL conversion.

Same SELECT ... FORMAT JSONEachRow, in-process, no server.
Run ./generate.sh first to create ./data/events.csv.
"""
import chdb

# Convert events.csv -> events_chdb.jsonl. INTO OUTFILE writes the file;
# the same JSONEachRow format produces one JSON object per line.
chdb.query("""
    SELECT * FROM file('data/events.csv')
    INTO OUTFILE 'data/events_chdb.jsonl' TRUNCATE
    FORMAT JSONEachRow
""")

# Show the first few lines we just wrote.
with open("data/events_chdb.jsonl") as f:
    for _ in range(3):
        print(f.readline().rstrip())

# Read the JSONL straight back to prove the round-trip.
print(chdb.query("""
    SELECT country, count() AS events
    FROM file('data/events_chdb.jsonl')
    GROUP BY country ORDER BY events DESC, country
""", "CSV"), end="")
