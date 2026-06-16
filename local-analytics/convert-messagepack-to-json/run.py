#!/usr/bin/env python3
"""chDB equivalent of the MsgPack -> JSON conversion.

Same ClickHouse SQL, same explicit MsgPack structure, run in-process with no
server. Reads ./data/events.msgpack and writes ./data/events_chdb.jsonl.
Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

STRUCT = "event_id UInt64, ts DateTime, event_type String, country String, amount Float64"

# MsgPack has no embedded schema, so the read needs an explicit structure.
sql = (
    f"SELECT * FROM file('events.msgpack', MsgPack, '{STRUCT}') "
    "INTO OUTFILE 'events_chdb.jsonl' TRUNCATE FORMAT JSONEachRow"
)
chdb.query(sql)

# Show the first three lines of the JSON we just wrote.
with open("events_chdb.jsonl") as f:
    for line in list(f)[:3]:
        print(line.rstrip())
