#!/usr/bin/env bash
# The exact commands from the article "How to convert BSON to JSON".
# Run ./generate.sh first to create the sample BSON in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert BSON -> NDJSON (one JSON object per line) =="
clickhouse local -q "SELECT * FROM file('users.bson') INTO OUTFILE 'users.jsonl' TRUNCATE FORMAT JSONEachRow"
cat users.jsonl

echo
echo "== 2. The schema clickhouse-local inferred from the BSON =="
clickhouse local -q "DESCRIBE file('users.bson')"

echo
echo "== 3. Convert to a single pretty JSON array (FORMAT JSON) =="
clickhouse local -q "SELECT * FROM file('users.bson') INTO OUTFILE 'users.json' TRUNCATE FORMAT JSON"
head -c 600 users.json
echo

echo
echo "== 4. Filter / reshape while converting (only active users, flatten one nested field) =="
clickhouse local -q "
SELECT _id, name, address['zip'] AS zip, tags
FROM file('users.bson')
WHERE active
INTO OUTFILE 'active.jsonl' TRUNCATE FORMAT JSONEachRow
"
cat active.jsonl

echo
echo "== 5. Perf: convert the ~162 MB, 2,000,000-doc events.bson to NDJSON (best-of-3, warm) =="
Q="SELECT * FROM file('events.bson') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_bson_time.txt
  echo "run $i: $(grep real /tmp/_bson_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('events.jsonl')"
ls -la events.jsonl
