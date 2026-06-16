#!/usr/bin/env bash
# The exact commands from the article "Run SQL across multiple CSV/Parquet files".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read many CSVs as one table with a glob =="
clickhouse local -q "SELECT count() FROM file('sales/*.csv')"

echo
echo "== 2. Aggregate across every file in one query =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue),2) AS revenue
FROM file('sales/*.csv')
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 3. Attribute rows to their source file with the _file virtual column =="
clickhouse local -q "
SELECT _file, count() AS rows, round(sum(revenue),2) AS revenue
FROM file('sales/*.csv')
GROUP BY _file
ORDER BY _file
FORMAT PrettyCompact"

echo
echo "== 4. Same idea on Parquet: glob a directory of parts =="
clickhouse local -q "
SELECT _file, count() AS rows
FROM file('events/*.parquet')
GROUP BY _file
ORDER BY _file
FORMAT PrettyCompact"

echo
echo "== 5. _path gives the full absolute path per row =="
clickhouse local -q "SELECT DISTINCT _path FROM file('events/*.parquet') ORDER BY _path FORMAT PrettyCompact"

echo
echo "== 6. Brace and range globs select a subset of files =="
echo "brace {01,02}:"
clickhouse local -q "SELECT count() FROM file('sales/2026-{01,02}.csv')"
echo "range {01..03}:"
clickhouse local -q "SELECT count() FROM file('sales/2026-{01..03}.csv')"

echo
echo "== 7. Perf: aggregate 12 CSVs / 3,000,000 rows in one query (best-of-3, warm) =="
Q="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('sales_large/*.csv') GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_multi_time.txt
  echo "run $i: $(grep real /tmp/_multi_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
