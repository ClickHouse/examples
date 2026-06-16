#!/usr/bin/env bash
# The exact commands from the article "How to read a semicolon-separated file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# A semicolon-delimited file with a header is CustomSeparatedWithNames with a
# ';' field delimiter and CSV-style escaping. Reused across the steps below.
SEMI="format_custom_field_delimiter = ';', format_custom_escaping_rule = 'CSV', format_custom_row_after_delimiter = '\n'"

echo "== 1. Read the first 10 rows (';' delimiter, header auto-detected) =="
clickhouse local -q "
SELECT * FROM file('orders.csv', CustomSeparatedWithNames)
LIMIT 10
SETTINGS $SEMI
FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred schema (names from the header, types from the data) =="
clickhouse local -q "
DESCRIBE file('orders.csv', CustomSeparatedWithNames)
SETTINGS $SEMI
FORMAT PrettyCompact"

echo
echo "== 3. Aggregate directly on the semicolon file, no import step =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue, round(avg(quantity), 2) AS avg_qty
FROM file('orders.csv', CustomSeparatedWithNames)
GROUP BY country ORDER BY revenue DESC
SETTINGS $SEMI
FORMAT PrettyCompact
"

echo
echo "== 4. GOTCHA: European decimal commas (revenue '1234,50') infer as String =="
clickhouse local -q "
DESCRIBE file('orders_eu.csv', CustomSeparatedWithNames)
SETTINGS $SEMI
FORMAT PrettyCompact"

echo
echo "== 5. Fix: convert decimal-comma text to a number with replaceOne(...)::Float64 =="
clickhouse local -q "
SELECT
  country,
  replaceOne(revenue, ',', '.')::Float64 AS revenue_eur
FROM file('orders_eu.csv', CustomSeparatedWithNames)
ORDER BY revenue_eur DESC
SETTINGS $SEMI
FORMAT PrettyCompact"

echo
echo "== 6. Aggregate the converted European values =="
clickhouse local -q "
SELECT round(sum(replaceOne(revenue, ',', '.')::Float64), 2) AS total_eur
FROM file('orders_eu.csv', CustomSeparatedWithNames)
SETTINGS $SEMI
FORMAT PrettyCompact"

echo
echo "== 7. Perf: aggregate the 3M-row, ~110 MB orders_large.csv (best-of-3, warm) =="
QBODY="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('orders_large.csv', CustomSeparatedWithNames) GROUP BY country ORDER BY revenue DESC"
Q="$QBODY SETTINGS $SEMI"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_semi_time.txt
  echo "run $i: $(grep real /tmp/_semi_time.txt)"
done
clickhouse local -q "$QBODY LIMIT 5 SETTINGS $SEMI FORMAT PrettyCompact"
