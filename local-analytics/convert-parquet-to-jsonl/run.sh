#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to JSONL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> JSONL (one object per line) =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
echo "first 3 lines:"
head -n 3 events.jsonl

echo
echo "== 2. Schema is read from the Parquet footer; types carry into JSON =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. The Map column becomes a nested JSON object, not a flattened string =="
clickhouse local -q "SELECT attrs FROM file('events.jsonl') LIMIT 3 FORMAT JSONEachRow"

echo
echo "== 4. Filter / reshape on the way out (any SQL works) =="
clickhouse local -q "
SELECT event_id, country, amount
FROM file('events.parquet')
WHERE action = 'purchase'
ORDER BY amount DESC
INTO OUTFILE 'purchases.jsonl' TRUNCATE FORMAT JSONEachRow
"
head -n 3 purchases.jsonl

echo
echo "== 5. Compress on the way out: .jsonl.gz is auto-detected =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"
ls -la events.jsonl events.jsonl.gz
echo "read the .gz back transparently:"
clickhouse local -q "SELECT count() FROM file('events.jsonl.gz')"

echo
echo "== 6. Perf: convert the 3,000,000-row events_large.parquet (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_p2j_time.txt
  echo "run $i: $(grep real /tmp/_p2j_time.txt)"
done
ls -la events_large.jsonl
