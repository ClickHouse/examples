#!/usr/bin/env python3
"""chDB equivalent of run.sh: convert Parquet -> ORC in-process, no server.
Run ./generate.sh first to create ./data/events.parquet."""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert Parquet -> ORC. Same SELECT ... INTO OUTFILE ... FORMAT ORC as the CLI,
# run inside Python with chDB.
chdb.query(
    "SELECT * FROM file('events.parquet') "
    "INTO OUTFILE 'events_chdb.orc' TRUNCATE FORMAT ORC"
)
print("wrote events_chdb.orc")

# Verify: same aggregate from the ORC file, returned as a pandas DataFrame.
df = chdb.query(
    "SELECT country, count() AS c, round(sum(amount), 2) AS amount "
    "FROM file('events_chdb.orc') GROUP BY country ORDER BY country",
    "DataFrame",
)
print(df.to_string(index=False))
