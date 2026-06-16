#!/usr/bin/env bash
# The exact commands from the article "How to convert ORC to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert ORC -> NDJSON (one object per line) in one line =="
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
head -3 events.jsonl

echo
echo "== 2. Inspect the schema ORC carried into the conversion =="
clickhouse local -q "DESCRIBE file('events.orc')"

echo
echo "== 3. Convert ORC -> a single JSON array (with metadata) =="
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.json' TRUNCATE FORMAT JSON"
head -28 events.json

echo
echo "== 4. Filter/shape during conversion (only purchases, flattened struct) =="
clickhouse local -q "
SELECT event_id, event_date, country, amount, source.platform AS platform
FROM file('events.orc')
WHERE action = 'purchase'
INTO OUTFILE 'purchases.jsonl' TRUNCATE FORMAT JSONEachRow"
cat purchases.jsonl

echo
echo "== 5. Keep Decimal/Int64 exact as JSON strings (lossless for big numbers) =="
clickhouse local -q "
SELECT event_id, amount FROM file('events.orc') LIMIT 3
FORMAT JSONEachRow
SETTINGS output_format_json_quote_64bit_integers = 1, output_format_json_quote_decimals = 1"

echo
echo "== 6. Perf: convert the 3,000,000-row events_large.orc -> NDJSON (best-of-3, warm) =="
CMD="SELECT * FROM file('events_large.orc') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$CMD" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_orc_time.txt
  echo "run $i: $(grep real /tmp/_orc_time.txt)"
done
echo "rows written: $(wc -l < events_large.jsonl)"
echo "output size: $(du -h events_large.jsonl | cut -f1)"
