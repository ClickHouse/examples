#!/usr/bin/env bash
# The exact commands from the article "How to read a pipe-delimited file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# Pipe-delimited files are read with the CustomSeparated family.
# Two settings define "pipe-delimited": the field delimiter and the per-field
# escaping rule (CSV = strip surrounding double-quotes, like a normal CSV cell).
PIPE="format_custom_field_delimiter='|', format_custom_escaping_rule='CSV'"

echo "== 1. Read the first 5 rows (header row -> column names) =="
clickhouse local -q "
SELECT * FROM file('orders.psv', 'CustomSeparatedWithNames')
LIMIT 5
SETTINGS $PIPE
"

echo
echo "== 2. Inspect the inferred schema =="
clickhouse local -q "
DESCRIBE file('orders.psv', 'CustomSeparatedWithNames')
SETTINGS $PIPE
"

echo
echo "== 3. The gotcha: drop format_custom_escaping_rule='CSV' and the quotes are NOT stripped =="
echo "   (the whole line collapses into one String column named with the quoted header)"
clickhouse local -q "
DESCRIBE file('orders.psv', 'CustomSeparatedWithNames')
SETTINGS format_custom_field_delimiter='|'
"

echo
echo "== 4. Aggregate directly on the pipe-delimited file =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),2) AS avg_qty
FROM file('orders.psv', 'CustomSeparatedWithNames')
GROUP BY country
ORDER BY revenue DESC
SETTINGS $PIPE
"

echo
echo "== 5. No header row? Use CustomSeparated + an explicit schema =="
clickhouse local -q "
SELECT * FROM file('orders_nohdr.psv', 'CustomSeparated',
  'order_date Date, order_id UInt32, country String, product String, revenue Float64, quantity UInt8')
ORDER BY revenue DESC LIMIT 3
SETTINGS $PIPE
"

echo
echo "== 6. Set the format once with SET, then query normally =="
clickhouse local -q "
SET format_custom_field_delimiter='|', format_custom_escaping_rule='CSV';
SELECT count() FROM file('orders.psv', 'CustomSeparatedWithNames');
"

echo
echo "== 7. Gzipped pipe-delimited (.psv.gz) reads transparently =="
clickhouse local -q "
SELECT * FROM file('orders.psv', 'CustomSeparatedWithNames')
INTO OUTFILE 'orders.psv.gz' TRUNCATE FORMAT CustomSeparatedWithNames
SETTINGS $PIPE
"
clickhouse local -q "
SELECT country, count() FROM file('orders.psv.gz', 'CustomSeparatedWithNames')
GROUP BY country ORDER BY country
SETTINGS $PIPE
"

echo
echo "== 8. Perf: aggregate the 3M-row, ~126 MB orders_large.psv (best-of-3, warm) =="
Q="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('orders_large.psv', 'CustomSeparatedWithNames') GROUP BY country ORDER BY revenue DESC LIMIT 5 SETTINGS $PIPE"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_psv_time.txt
  echo "run $i: $(grep real /tmp/_psv_time.txt)"
done
clickhouse local -q "$Q"
