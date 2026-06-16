#!/usr/bin/env bash
# The exact commands from the article "How to convert JSONL to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. The naive convert: SELECT * loses nested structure =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_naive.csv' TRUNCATE FORMAT CSVWithNames"
head -n 4 events_naive.csv

echo
echo "== 2. Inspect the inferred schema (geo is a Tuple, tags is an Array) =="
clickhouse local -q "DESCRIBE file('events.jsonl')"

echo
echo "== 3. The correct convert: flatten nested fields into scalar columns =="
clickhouse local -q "
SELECT
  event_id,
  ts,
  action,
  geo.country AS geo_country,
  geo.city    AS geo_city,
  arrayStringConcat(tags, '|') AS tags
FROM file('events.jsonl')
INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames
"
cat events.csv

echo
echo "== 4. Read the CSV back to confirm the round-trip =="
clickhouse local -q "SELECT geo_country, count() AS events FROM file('events.csv') GROUP BY geo_country ORDER BY geo_country"

echo
echo "== 5. Perf: convert the 1.2M-row events_large.jsonl (best-of-3, warm) =="
Q="SELECT event_id, ts, action, geo.country AS geo_country, geo.city AS geo_city, arrayStringConcat(tags, '|') AS tags FROM file('events_large.jsonl') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q" >/dev/null 2>&1   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" >/dev/null 2> /tmp/_jsonl_csv_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_csv_time.txt)"
done
echo "rows written (incl header): $(wc -l < events_large.csv)"
