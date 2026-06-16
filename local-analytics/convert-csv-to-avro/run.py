#!/usr/bin/env python3
"""Convert CSV to Avro in Python with chDB (the same SELECT ... FORMAT Avro,
in-process). Run ./generate.sh first to create ./data/events.csv.

chDB is the embedded ClickHouse engine for Python: no server, no import step.
"""
import pathlib
import chdb

DATA = pathlib.Path(__file__).parent / "data"
src = DATA / "events.csv"
dst = DATA / "events_chdb.avro"

# 1. Convert: read the CSV with file(), write Avro bytes, save to disk.
#    The Avro schema is derived from the types chDB infers from the CSV.
avro_bytes = chdb.query(
    f"SELECT * FROM file('{src}', 'CSVWithNames') FORMAT Avro"
).bytes()
dst.write_bytes(avro_bytes)
print(f"wrote {dst.name} ({len(avro_bytes)} bytes)")

# 2. Read it straight back and confirm the round-trip.
print(chdb.query(f"SELECT * FROM file('{dst}') ORDER BY amount DESC LIMIT 5"))

# 3. Inspect the schema carried into the Avro file.
print(chdb.query(f"DESCRIBE file('{dst}')"))
