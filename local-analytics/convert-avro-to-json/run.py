#!/usr/bin/env python3
# The chDB equivalent of the Avro -> JSON conversion in the article.
# Same SELECT ... FORMAT, in-process, written to a file. No server.
# Run ./generate.sh first to create ./data/events.avro.
import os
import chdb

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))

# Convert Avro -> JSON Lines, casting the DateTime back from Avro's epoch int.
sql = """
SELECT event_id, event_type, country, amount, ts::DateTime AS ts
FROM file('events.avro')
FORMAT JSONEachRow
"""
jsonl = chdb.query(sql).bytes()
with open("events_chdb.jsonl", "wb") as f:
    f.write(jsonl)

print("== chDB: first 5 lines of events_chdb.jsonl ==")
for line in jsonl.decode().splitlines()[:5]:
    print(line)
