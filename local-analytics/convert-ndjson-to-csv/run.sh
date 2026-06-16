#!/usr/bin/env bash
# The exact commands from the article "How to convert NDJSON to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. The naive one-liner: SELECT * (watch what happens to nested fields) =="
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
echo "header columns: $(head -n 1 events.csv | tr ',' '\n' | wc -l | tr -d ' ')"
echo "data columns:   $(sed -n '2p' events.csv | tr ',' '\n' | wc -l | tr -d ' ')"
head -n 3 events.csv

echo
echo "== 2. Why: the nested 'device' object is inferred as a Tuple =="
clickhouse local -q "DESCRIBE file('events.ndjson')"

echo
echo "== 3. The correct conversion: flatten nested fields, serialise the array as a JSON string =="
clickhouse local -q "
SELECT
  event_id,
  ts,
  country,
  action,
  amount,
  device.os          AS device_os,
  device.app_version AS device_version,
  toJSONString(tags) AS tags
FROM file('events.ndjson')
INTO OUTFILE 'events_flat.csv' TRUNCATE FORMAT CSVWithNames
"
echo "header columns: $(head -n 1 events_flat.csv | tr ',' '\n' | wc -l | tr -d ' ')"
echo "data columns:   $(sed -n '2p' events_flat.csv | tr ',' '\n' | wc -l | tr -d ' ')"
head -n 3 events_flat.csv

echo
echo "== 4. Read the flat CSV back: clean tabular data, types preserved =="
clickhouse local -q "SELECT country, count() AS events, round(sum(amount),2) AS total FROM file('events_flat.csv') GROUP BY country ORDER BY total DESC"

echo
echo "== 5. Perf: convert the 1,000,000-row, ~151 MB events_large.ndjson (best-of-3, warm) =="
Q="SELECT event_id, ts, country, action, amount, device.os AS device_os, device.app_version AS device_version, toJSONString(tags) AS tags FROM file('events_large.ndjson') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" 2> /tmp/_ndjson_csv_time.txt
  echo "run $i: $(grep real /tmp/_ndjson_csv_time.txt)"
done
echo "rows written: $(clickhouse local -q "SELECT count() FROM file('events_large.csv')")"
ls -la events_large.csv
