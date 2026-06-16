#!/usr/bin/env bash
# The exact commands from the article "How to run SQL on a JSONL file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows (JSONEachRow: one JSON object per line) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred schema (keys -> columns, types from the values) =="
clickhouse local -q "DESCRIBE file('events.jsonl') FORMAT PrettyCompact"

echo
echo "== 3. Filter, aggregate, and group by directly on the JSONL =="
clickhouse local -q "
SELECT country, count() AS purchases, round(sum(revenue), 2) AS revenue, round(avg(quantity), 3) AS avg_qty
FROM file('events.jsonl')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact
"

echo
echo "== 4. The extension does not matter: .ndjson / .json read the same way =="
clickhouse local -q "SELECT count() FROM file('events.jsonl', JSONEachRow)"

echo
echo "== 5. Read a gzipped JSONL transparently (.jsonl.gz) =="
clickhouse local -q "SELECT country, count() FROM file('events.jsonl.gz') GROUP BY country ORDER BY country FORMAT PrettyCompact"

echo
echo "== 6. Convert JSONL -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 7. Perf: aggregate the 3M-row, ~342 MB events_large.jsonl (best-of-3, warm) =="
Q="SELECT country, count(), round(sum(revenue),2) AS revenue, round(avg(quantity),3) FROM file('events_large.jsonl') WHERE event_type = 'purchase' GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_jsonl_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
