#!/usr/bin/env bash
# The exact commands from the article "How to convert TSV to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert TSV -> JSON (JSONEachRow: one JSON object per line / NDJSON) =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
echo "first 3 lines of events.jsonl:"
head -3 events.jsonl

echo
echo "== 2. Inspect the inferred schema (names from the header, types from the data) =="
clickhouse local -q "DESCRIBE file('events.tsv')"

echo
echo "== 3. Convert TSV -> a single JSON array (output_format_json_array_of_rows=1) =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.json' TRUNCATE FORMAT JSONEachRow" --output_format_json_array_of_rows=1
echo "first 4 lines of events.json:"
head -4 events.json

echo
echo "== 4. Transform on the way out (project, filter, rename) =="
clickhouse local -q "
SELECT event_date, country, upper(action) AS action_upper, value
FROM file('events.tsv')
WHERE action = 'purchase'
ORDER BY value DESC
LIMIT 3
INTO OUTFILE 'purchases.jsonl' TRUNCATE FORMAT JSONEachRow"
cat purchases.jsonl

echo
echo "== 5. Nest flat columns into a JSON object =="
clickhouse local -q "
SELECT event_id, map('country', country, 'action', action) AS attrs, value
FROM file('events.tsv')
LIMIT 3
INTO OUTFILE 'nested.jsonl' TRUNCATE FORMAT JSONEachRow"
cat nested.jsonl

echo
echo "== 6. Gzip the JSON on the way out (.jsonl.gz, inferred from the extension) =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"
echo "events.jsonl.gz written; read it straight back:"
clickhouse local -q "SELECT count() FROM file('events.jsonl.gz', 'JSONEachRow')"

echo
echo "== 7. Perf: convert the 3M-row, ~105 MB events_large.tsv to JSONEachRow (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.tsv') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null 2>&1   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_tsvjson_time.txt
  echo "run $i: $(grep real /tmp/_tsvjson_time.txt)"
done
echo "output size:"
ls -lh events_large.jsonl | awk '{print $5, $9}'
echo "row count of the JSON output:"
clickhouse local -q "SELECT count() FROM file('events_large.jsonl', 'JSONEachRow')"
