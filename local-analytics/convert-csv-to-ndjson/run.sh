#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to NDJSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> NDJSON in one line =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.ndjson' TRUNCATE FORMAT JSONEachRow"
echo "wrote events.ndjson"

echo
echo "== 2. Look at the result (one JSON object per line) =="
head -n 5 events.ndjson

echo
echo "== 3. Confirm the inferred types carried into the JSON =="
clickhouse local -q "DESCRIBE file('events.csv')"

echo
echo "== 4. Round-trip: read the NDJSON straight back, schema re-inferred =="
clickhouse local -q "SELECT country, count() AS events, round(sum(value),2) AS total FROM file('events.ndjson') GROUP BY country ORDER BY total DESC"

echo
echo "== 5. Force string columns when inference would guess wrong (e.g. zero-padded ids) =="
clickhouse local -q "
SELECT * FROM file('events.csv', 'CSVWithNames',
  'event_date Date, event_id String, country String, action String, value Float64, count UInt8')
INTO OUTFILE 'events_typed.ndjson' TRUNCATE FORMAT JSONEachRow"
head -n 2 events_typed.ndjson

echo
echo "== 6. Throughput: convert the 3M-row, ~123 MB events_large.csv (best-of-3, warm) =="
CMD="SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.ndjson' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$CMD" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_ndjson_time.txt
  echo "run $i: $(grep real /tmp/_ndjson_time.txt)"
done
echo "output size:"
ls -la events_large.ndjson | awk '{print $5, $NF}'
echo "row count check (CSV vs NDJSON):"
clickhouse local -q "SELECT (SELECT count() FROM file('events_large.csv')) AS csv_rows, (SELECT count() FROM file('events_large.ndjson')) AS ndjson_rows"
