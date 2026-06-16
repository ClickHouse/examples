#!/usr/bin/env python3
"""chDB equivalent of the CSV -> ORC conversion (Surface B).

Same ClickHouse SQL as run.sh, in-process via chDB. Run ./generate.sh first.
"""
import chdb

# 1. Convert CSV -> ORC in one line (in-process, no server).
chdb.query("SELECT * FROM file('data/events.csv') INTO OUTFILE 'data/events_chdb.orc' TRUNCATE FORMAT ORC")
print("wrote data/events_chdb.orc")

# 2. Types carried from CSV into ORC.
print(chdb.query("DESCRIBE file('data/events_chdb.orc')", "TabSeparated"), end="")

# 3. Read it back / aggregate on the ORC directly.
print(chdb.query("SELECT * FROM file('data/events_chdb.orc') LIMIT 5", "CSV"), end="")
print(chdb.query("SELECT count() FROM file('data/events_chdb.orc')", "CSV"), end="")
