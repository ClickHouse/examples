#!/usr/bin/env python3
"""chDB equivalent of the Parquet -> JSON conversion.

Same SQL, in-process, no server. Run ./generate.sh first to create ./data/.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert Parquet -> JSONL (one object per line). chDB returns the bytes;
#    write them to a file.
out = chdb.query(
    "SELECT * FROM file('events.parquet') ORDER BY event_id FORMAT JSONEachRow"
)
with open("events_chdb.jsonl", "w") as f:
    f.write(str(out))

print("== events_chdb.jsonl, first 2 lines ==")
with open("events_chdb.jsonl") as f:
    for _ in range(2):
        print(f.readline().rstrip())

# 2. Typed + nested columns (Date, Decimal, Array, named Tuple) carry through.
print("\n== nested columns in JSON ==")
print(
    chdb.query(
        "SELECT event_id, tags, account FROM file('events.parquet') "
        "ORDER BY event_id LIMIT 2 FORMAT JSONEachRow"
    ),
    end="",
)

# 3. Filter / reshape while converting -- it is just SQL.
print("\n== reshape while converting ==")
print(
    chdb.query(
        "SELECT country, count() AS events, round(sum(amount), 2) AS total "
        "FROM file('events.parquet') GROUP BY country ORDER BY total DESC "
        "FORMAT JSONEachRow"
    ),
    end="",
)
