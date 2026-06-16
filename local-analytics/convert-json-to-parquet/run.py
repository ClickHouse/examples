#!/usr/bin/env python3
"""Convert JSON to Parquet with chDB (the in-process ClickHouse engine).

Mirrors run.ipynb. Run ./generate.sh first to create ./data/events.json.
The conversion is the same SELECT ... INTO OUTFILE ... FORMAT Parquet you'd
run on the CLI, executed in-process from Python.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert JSON -> Parquet in one statement.
chdb.query(
    "SELECT * FROM file('events.json') "
    "INTO OUTFILE 'events_chdb.parquet' TRUNCATE FORMAT Parquet"
)
print("wrote events_chdb.parquet")

# 2. Schema carried from JSON into Parquet (the nested geo object stays typed).
print(chdb.query("DESCRIBE file('events_chdb.parquet')", "DataFrame")[["name", "type"]])

# 3. Read the typed columns back, including the nested fields.
print(chdb.query(
    "SELECT event_id, geo.country AS country, geo.city AS city, tags, amount "
    "FROM file('events_chdb.parquet') ORDER BY event_id LIMIT 5",
    "PrettyCompact",
))

# 4. Or pull the result straight into a pandas DataFrame.
df = chdb.query(
    "SELECT geo.country AS country, count() AS events, round(sum(amount), 2) AS total "
    "FROM file('events_chdb.parquet') GROUP BY country ORDER BY total DESC",
    "DataFrame",
)
print(df)
