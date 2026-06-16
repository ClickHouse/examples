#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> JSON (one object per line: JSONEachRow / NDJSON) =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
echo "wrote events.jsonl; first 3 lines:"
head -n 3 events.jsonl

echo
echo "== 2. Same data as a single JSON array (FORMAT JSON) =="
clickhouse local -q "SELECT event_id, country, amount, tags, account FROM file('events.parquet') ORDER BY event_id LIMIT 2 INTO OUTFILE 'events.json' TRUNCATE FORMAT JSON"
echo "wrote events.json:"
cat events.json

echo
echo "== 3. The schema clickhouse-local read from the Parquet footer =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 4. Typed + nested columns carry into JSON (Date, Decimal, Array, named Tuple) =="
clickhouse local -q "SELECT * FROM file('events.parquet') ORDER BY event_id LIMIT 2 FORMAT JSONEachRow"

echo
echo "== 5. Stringify 64-bit ints to survive JSON parsers (output_format_json_quote_64bit_integers) =="
clickhouse local -q "SELECT event_id, amount FROM file('events.parquet') ORDER BY event_id LIMIT 2 FORMAT JSONEachRow SETTINGS output_format_json_quote_64bit_integers = 1"

echo
echo "== 6. Filter / reshape while converting (it is just SQL) =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount), 2) AS total
FROM file('events.parquet')
GROUP BY country
ORDER BY total DESC
FORMAT JSONEachRow"

echo
echo "== 7. Throughput: convert the ~3M-row events_large.parquet -> JSONL (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"  # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow" 2> /tmp/_p2j_time.txt
  echo "run $i: $(grep real /tmp/_p2j_time.txt)"
done
echo "rows in events_large.jsonl: $(wc -l < events_large.jsonl)"
echo "size of events_large.jsonl: $(du -h events_large.jsonl | cut -f1)"
