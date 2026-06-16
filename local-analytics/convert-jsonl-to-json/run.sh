#!/usr/bin/env bash
# The exact commands from the article "How to convert JSONL to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert JSONL -> a single JSON array (the one-liner) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_array.json' TRUNCATE FORMAT JSONEachRow SETTINGS output_format_json_array_of_rows = 1"
cat events_array.json

echo
echo "== 2. Schema is auto-inferred from the JSONL =="
clickhouse local -q "DESCRIBE file('events.jsonl')"

echo
echo "== 3. Alternative: FORMAT JSON writes the ClickHouse envelope (meta + data + stats) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_envelope.json' TRUNCATE FORMAT JSON"
cat events_envelope.json

echo
echo "== 4. Round-trip: read the array back (JSONEachRow reads a top-level array) =="
clickhouse local -q "SELECT count() AS rows, round(sum(amount), 2) AS total FROM file('events_array.json', 'JSONEachRow')"

echo
echo "== 5. Throughput: convert the 3,000,000-row events_large.jsonl (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.jsonl') INTO OUTFILE 'events_large.json' TRUNCATE FORMAT JSONEachRow SETTINGS output_format_json_array_of_rows = 1"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_jsonl_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_time.txt)"
done
clickhouse local -q "SELECT count() FROM file('events_large.json', 'JSONEachRow')"
