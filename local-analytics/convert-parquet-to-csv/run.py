#!/usr/bin/env python3
"""chDB equivalent of the Parquet -> CSV conversion. Same SQL, in-process Python.
Run ./generate.sh first to create ./data/events.parquet.
Requires: pip install chdb
"""
import chdb

# Convert Parquet -> CSV with a header. INTO OUTFILE writes the file; the same
# SELECT ... FORMAT works as in clickhouse-local.
chdb.query("""
SELECT * FROM file('data/events.parquet')
INTO OUTFILE 'data/events_chdb.csv' TRUNCATE FORMAT CSVWithNames
""")

with open("data/events_chdb.csv") as f:
    print("First 4 lines of data/events_chdb.csv:")
    for _ in range(4):
        print(f.readline().rstrip())

# Verify the round-trip row count.
print("\nRow count in the CSV:")
print(str(chdb.query("SELECT count() FROM file('data/events_chdb.csv')", "CSV")).rstrip())
