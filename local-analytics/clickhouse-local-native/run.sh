#!/usr/bin/env bash
# The exact commands from the article "How to read a ClickHouse Native format file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows (no schema needed; Native is self-describing) =="
clickhouse local -q "SELECT * FROM file('events.native') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. DESCRIBE: the EXACT types are read from the file, not inferred =="
clickhouse local -q "DESCRIBE file('events.native') FORMAT PrettyCompact"

echo
echo "== 3. For contrast: the same rows as CSV, types are guessed (Nullable, lossy) =="
clickhouse local -q "DESCRIBE file('events.csv') FORMAT PrettyCompact"

echo
echo "== 4. Aggregate directly on the Native file =="
clickhouse local -q "
SELECT country, count() AS events, sum(revenue) AS revenue, round(avg(quantity), 2) AS avg_qty
FROM file('events.native')
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 5. Native is the wire format: pipe it between two processes, schema travels with it =="
clickhouse local -q "SELECT number AS id, (number * number)::UInt64 AS sq FROM numbers(3) FORMAT Native" \
  | clickhouse local --input-format Native -q "SELECT * FROM table FORMAT PrettyCompact"

echo
echo "== 6. Read a gzipped Native file transparently (.native.gz) =="
clickhouse local -q "SELECT count(), sum(revenue) FROM file('events.native.gz') FORMAT PrettyCompact"

echo
echo "== 7. Perf: aggregate the 3,000,000-row events_large.native (best-of-3, warm) =="
Q="SELECT country, count() AS events, sum(revenue) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.native') GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_nat_time.txt
  echo "run $i: $(grep real /tmp/_nat_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
