#!/usr/bin/env bash
# The exact commands from the article "How to convert JSON to JSONL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. The one-liner: top-level JSON array -> one object per line (JSONL) =="
clickhouse local -q "SELECT * FROM file('events.json', JSONEachRow) INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
cat events.jsonl

echo
echo "== 2. Schema inferred straight from the JSON (nested fields kept) =="
clickhouse local -q "DESCRIBE file('events.json', JSONEachRow)"

echo
echo "== 3. Confirm the line count == the array length =="
echo -n "array elements: "; clickhouse local -q "SELECT count() FROM file('events.json', JSONEachRow)"
echo -n "jsonl lines:    "; wc -l < events.jsonl

echo
echo "== 4. Filter / reshape while you convert =="
clickhouse local -q "
SELECT id, country, amount, user.name AS name
FROM file('events.json', JSONEachRow)
WHERE event = 'purchase'
INTO OUTFILE 'purchases.jsonl' TRUNCATE FORMAT JSONEachRow"
cat purchases.jsonl

echo
echo "== 5. Write gzipped JSONL directly (extension picks the codec) =="
clickhouse local -q "SELECT * FROM file('events.json', JSONEachRow) INTO OUTFILE 'events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"
ls -la events.jsonl.gz

echo
echo "== 6. Perf: convert the ~226 MB, 2,000,000-element array (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.json', JSONEachRow) INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_json2jsonl_time.txt
  echo "run $i: $(grep real /tmp/_json2jsonl_time.txt)"
done
echo -n "output lines: "; wc -l < events_large.jsonl
