#!/usr/bin/env bash
# The exact commands from the article "How to convert Avro to JSON".
# Run ./generate.sh first to create the sample Avro files in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Avro -> JSON Lines (one object per line) =="
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
head -n 5 events.jsonl

echo
echo "== 2. Inspect the schema Avro embedded (read needs no structure argument) =="
clickhouse local -q "DESCRIBE file('events.avro')"

echo
echo "== 3. Gotcha: DateTime arrives as an epoch int; cast it back for readable JSON =="
clickhouse local -q "
SELECT event_id, event_type, country, amount, ts::DateTime AS ts
FROM file('events.avro')
INTO OUTFILE 'events_typed.jsonl' TRUNCATE FORMAT JSONEachRow"
head -n 5 events_typed.jsonl

echo
echo "== 4. Convert to a single JSON array (FORMAT JSON) =="
clickhouse local -q "SELECT event_id, event_type, amount FROM file('events.avro') LIMIT 3 FORMAT JSON"

echo
echo "== 5. Filter / reshape during the conversion =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount), 2) AS total
FROM file('events.avro')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY total DESC
FORMAT JSONEachRow"

echo
echo "== 6. Write gzipped JSON Lines directly (.jsonl.gz, inferred from the name) =="
clickhouse local -q "SELECT event_id, event_type, ts::DateTime AS ts FROM file('events.avro') INTO OUTFILE 'events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"
ls -la events.jsonl.gz

echo
echo "== 7. Perf: convert the 3,000,000-row events_large.avro to JSON Lines (best-of-3, warm) =="
Q="SELECT event_id, event_type, country, amount, ts::DateTime AS ts FROM file('events_large.avro') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
echo "rows written: $(wc -l < events_large.jsonl)"
