#!/usr/bin/env bash
# The exact commands from the article "How to run SQL on a CSV file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 10 rows (header auto-detected) =="
clickhouse local -q "SELECT * FROM file('orders.csv') LIMIT 10"

echo
echo "== 2. Inspect the inferred schema (column names from the header, types from the data) =="
clickhouse local -q "DESCRIBE file('orders.csv')"

echo
echo "== 3. Aggregate directly on the CSV, no import step =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue, round(avg(quantity), 2) AS avg_qty
FROM file('orders.csv')
GROUP BY country
ORDER BY revenue DESC
"

echo
echo "== 4. Override the inferred structure when you need to =="
clickhouse local -q "
SELECT * FROM file('orders.csv', 'CSVWithNames',
  'order_date Date, order_id UInt32, country String, product String, revenue Float64, quantity UInt8')
ORDER BY revenue DESC LIMIT 3
"

echo
echo "== 5. Convert CSV -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('orders.parquet')"

echo
echo "== 6. Read a gzipped CSV transparently (.csv.gz) =="
clickhouse local -q "SELECT country, count() FROM file('orders.csv.gz') GROUP BY country ORDER BY country"

echo
echo "== 7. Perf: aggregate the 8M-row, ~338 MB orders_large.csv (best-of-3, warm) =="
Q="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('orders_large.csv') GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_csv_time.txt
  echo "run $i: $(grep real /tmp/_csv_time.txt)"
done
clickhouse local -q "$Q LIMIT 5"
