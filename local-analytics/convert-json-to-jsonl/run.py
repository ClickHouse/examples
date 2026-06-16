#!/usr/bin/env python3
"""chDB equivalent of the JSON -> JSONL conversion (Surface B).

Same SQL as run.sh, in-process in Python. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Top-level JSON array -> one object per line (JSONL). Same SELECT ... FORMAT
# JSONEachRow, written straight to a file with INTO OUTFILE.
chdb.query(
    "SELECT * FROM file('events.json', JSONEachRow) "
    "INTO OUTFILE 'events_py.jsonl' TRUNCATE FORMAT JSONEachRow"
)

with open("events_py.jsonl") as f:
    print(f.read(), end="")

# The schema is inferred from the JSON, including the nested user object and the
# items array — both survive the round-trip (JSONL keeps nesting, unlike CSV).
print(chdb.query("DESCRIBE file('events.json', JSONEachRow)", "CSV"), end="")
