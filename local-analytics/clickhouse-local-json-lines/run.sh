#!/usr/bin/env bash
# The exact commands from the article "How to query a JSON Lines file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 5 rows (format detected from .jsonl, schema inferred) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') LIMIT 5"

echo
echo "== 2. Inspect the inferred schema, no CREATE TABLE =="
clickhouse local -q "DESCRIBE file('events.jsonl')"

echo
echo "== 3. Filter, group, aggregate directly on the file =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue), 2) AS revenue, round(avg(quantity), 2) AS avg_qty
FROM file('events.jsonl')
GROUP BY country
ORDER BY revenue DESC
"

echo
echo "== 4. JSONL, NDJSON, JSON Lines are the same format; .ndjson maps the same way =="
cp -f events.jsonl events.ndjson
clickhouse local -q "SELECT count() FROM file('events.ndjson')"

echo
echo "== 5. A file with an odd extension: name the format explicitly =="
cp -f events.jsonl events.txt
clickhouse local -q "SELECT count() FROM file('events.txt', JSONEachRow)"

echo
echo "== 6. JSONEachRow also reads a single top-level JSON array =="
printf '[{\"user_id\":1,\"country\":\"GB\"},{\"user_id\":2,\"country\":\"US\"}]' > array.json
clickhouse local -q "SELECT * FROM file('array.json', JSONEachRow)"

echo
echo "== 7. Read a gzipped JSON Lines file transparently (.jsonl.gz) =="
clickhouse local -q "SELECT country, count() FROM file('events.jsonl.gz') GROUP BY country ORDER BY country"

echo
echo "== 8. Perf: aggregate the 3M-row, ~360 MB events_large.jsonl (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.jsonl') GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_jsonl_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_time.txt)"
done
clickhouse local -q "$Q LIMIT 5"
