#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> CSV in one line (header included) =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
head -4 events.csv

echo
echo "== 2. Schema is read from the Parquet footer (no schema to declare) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Verify the row count survives the round-trip =="
clickhouse local -q "SELECT count() FROM file('events.csv')"

echo
echo "== 4. Nested column -> flat CSV (Map is serialized to one text cell) =="
clickhouse local -q "SELECT event_id, attrs FROM file('events.csv') LIMIT 3"

echo
echo "== 5. Flatten the Map into real CSV columns instead =="
clickhouse local -q "
SELECT event_date, country, attrs['os'] AS os, attrs['plan'] AS plan
FROM file('events.parquet')
INTO OUTFILE 'events_flat.csv' TRUNCATE FORMAT CSVWithNames"
head -4 events_flat.csv

echo
echo "== 6. Change the delimiter (e.g. semicolon for European Excel) =="
clickhouse local -q "
SELECT event_date, country, amount FROM file('events.parquet')
INTO OUTFILE 'events_semi.csv' TRUNCATE FORMAT CSVWithNames
SETTINGS format_csv_delimiter=';'"
head -4 events_semi.csv

echo
echo "== 7. No header? use FORMAT CSV instead of CSVWithNames =="
clickhouse local -q "SELECT * FROM file('events.parquet') LIMIT 3 INTO OUTFILE 'events_noheader.csv' TRUNCATE FORMAT CSV"
cat events_noheader.csv

echo
echo "== 8. Perf: convert the 3,000,000-row events_large.parquet (~211 MB CSV) (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_p2c_time.txt
  echo "run $i: $(grep real /tmp/_p2c_time.txt)"
done
clickhouse local -q "SELECT count() FROM file('events_large.csv')"
