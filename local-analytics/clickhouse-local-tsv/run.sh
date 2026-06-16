#!/usr/bin/env bash
# The exact commands from the article "How to read a TSV file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 10 rows (header auto-detected) =="
clickhouse local -q "SELECT * FROM file('orders.tsv') LIMIT 10"

echo
echo "== 2. Inspect the inferred schema (column names from the header, types from the data) =="
clickhouse local -q "DESCRIBE file('orders.tsv')"

echo
echo "== 3. Aggregate directly on the TSV, no import step =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue, round(avg(quantity), 2) AS avg_qty
FROM file('orders.tsv')
GROUP BY country
ORDER BY revenue DESC
"

echo
echo "== 4. A TSV with no header: use the TSV format and name the columns yourself =="
clickhouse local -q "
SELECT * FROM file('orders_nohdr.tsv', 'TSV',
  'order_date Date, order_id UInt32, country String, product String, revenue Float64, quantity UInt8')
ORDER BY revenue DESC LIMIT 3
"

echo
echo "== 5. Read a gzipped TSV transparently (.tsv.gz) =="
clickhouse local -q "SELECT country, count() FROM file('orders.tsv.gz') GROUP BY country ORDER BY country"

echo
echo "== 6. Convert TSV -> CSV in one line =="
clickhouse local -q "SELECT * FROM file('orders.tsv') INTO OUTFILE 'orders.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "SELECT count() FROM file('orders.csv')"

echo
echo "== 7. Schema inference is per-file: the 3M-row TSV infers revenue as String =="
clickhouse local -q "DESCRIBE file('orders_large.tsv')"

echo
echo "== 8. Pin the schema so revenue stays numeric, then aggregate (best-of-3, warm, ~110 MB) =="
S="order_date Date, order_id UInt32, country String, product String, revenue Float64, quantity UInt8"
Q="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('orders_large.tsv', 'TSVWithNames', '$S') GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_tsv_time.txt
  echo "run $i: $(grep real /tmp/_tsv_time.txt)"
done
clickhouse local -q "$Q LIMIT 5"
