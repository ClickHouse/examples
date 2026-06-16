#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to NDJSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> NDJSON in one line =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.ndjson' TRUNCATE FORMAT JSONEachRow"
echo "first 3 lines:"
head -n 3 events.ndjson

echo
echo "== 2. The schema is read from the Parquet footer (no -S needed) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Booleans: UInt8 0/1 by default, cast to Bool for true/false =="
clickhouse local -q "SELECT event_id, is_member::Bool AS is_member FROM file('events.parquet') LIMIT 2 FORMAT JSONEachRow"

echo
echo "== 4. Project / rename / filter while converting =="
clickhouse local -q "
SELECT event_id, country, amount
FROM file('events.parquet')
WHERE action = 'purchase'
ORDER BY amount DESC
LIMIT 3
INTO OUTFILE 'purchases.ndjson' TRUNCATE FORMAT JSONEachRow"
cat purchases.ndjson

echo
echo "== 5. Write compressed NDJSON straight away (.ndjson.gz) =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.ndjson.gz' TRUNCATE FORMAT JSONEachRow"
ls -la events.ndjson.gz
echo "read it straight back (gzip auto-detected):"
clickhouse local -q "SELECT count() FROM file('events.ndjson.gz')"

echo
echo "== 6. Throughput: convert the 3,000,000-row events_large.parquet (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.ndjson' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_p2n_time.txt
  echo "run $i: $(grep real /tmp/_p2n_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('events_large.ndjson')"
