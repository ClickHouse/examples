#!/usr/bin/env bash
# The exact commands from the article "Convert BSON to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert BSON -> CSV in one line (naive) =="
clickhouse local -q "SELECT * FROM file('events.bson') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
head -6 events.csv

echo
echo "== 2. Inspect the schema clickhouse-local inferred from the BSON =="
clickhouse local -q "DESCRIBE file('events.bson')"

echo
echo "== 3. The gotcha: the nested geo sub-document became one Map column =="
echo "   (look at the 'geo' field in events.csv above - it's a single quoted cell)"
clickhouse local -q "SELECT geo FROM file('events.bson') LIMIT 1"

echo
echo "== 4. Flatten the nested sub-document into real CSV columns =="
clickhouse local -q "
SELECT
  event_id,
  event_type,
  geo['city']    AS city,
  geo['country'] AS country,
  amount
FROM file('events.bson')
INTO OUTFILE 'events_flat.csv' TRUNCATE FORMAT CSVWithNames"
head -6 events_flat.csv

echo
echo "== 5. The flat CSV reads back with a clean, fully typed schema =="
clickhouse local -q "DESCRIBE file('events_flat.csv', CSVWithNames)"

echo
echo "== 6. Perf: convert the 1.4M-row, ~145 MB events_large.bson to CSV (best-of-3, warm) =="
Q="SELECT event_id, event_type, geo['city'] AS city, geo['country'] AS country, amount FROM file('events_large.bson') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" 2> /tmp/_bson_time.txt
  echo "run $i: $(grep real /tmp/_bson_time.txt)"
done
echo "rows in output CSV:"
clickhouse local -q "SELECT count() FROM file('events_large.csv', CSVWithNames)"

echo
echo "== 7. chDB Python equivalent (same SELECT, written to CSV) =="
python3 ../run.py
