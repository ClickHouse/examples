#!/usr/bin/env bash
# The exact commands from the article "How to convert JSON to TSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. The one-liner: JSON (JSONL) -> TSV =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_naive.tsv' TRUNCATE FORMAT TSVWithNames"
cat events_naive.tsv

echo
echo "== 2. Inspect the inferred schema: note user is a nested Tuple =="
clickhouse local -q "DESCRIBE file('events.jsonl')"

echo
echo "== 3. Flatten before TSV: promote nested fields to top-level columns =="
clickhouse local -q "
SELECT
  event_id,
  event_type,
  ts,
  user.id   AS user_id,
  user.plan AS user_plan,
  source,
  amount
FROM file('events.jsonl')
INTO OUTFILE 'events_flat.tsv' TRUNCATE FORMAT TSVWithNames
"
cat events_flat.tsv

echo
echo "== 4. Perf: flatten-convert 1M rows JSONL -> TSV (best-of-3, warm) =="
Q="SELECT event_id, event_type, ts, user.id AS user_id, user.plan AS user_plan, source, amount FROM file('events_large.jsonl') INTO OUTFILE 'events_large.tsv' TRUNCATE FORMAT TSVWithNames"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_json_tsv_time.txt
  echo "run $i: $(grep real /tmp/_json_tsv_time.txt)"
done
ls -la events_large.tsv
