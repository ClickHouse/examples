#!/usr/bin/env bash
# The exact commands from the article "How to read a file with a custom delimiter".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read a |~|-delimited file (header auto-detected) =="
clickhouse local -q "
SELECT * FROM file('orders.txt', CustomSeparatedWithNames)
LIMIT 5
SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"

echo
echo "== 2. Inspect the inferred schema with DESCRIBE =="
clickhouse local -q "
DESCRIBE file('orders.txt', CustomSeparatedWithNames)
SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"

echo
echo "== 3. Filter and group by, directly on the file =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('orders.txt', CustomSeparatedWithNames)
GROUP BY country
ORDER BY revenue DESC
SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"

echo
echo "== 4. Custom field AND row delimiter, no header =="
clickhouse local -q "
SELECT * FROM file('orders_pipe.txt', CustomSeparated,
  'order_id UInt32, country String, revenue Float64')
LIMIT 5
SETTINGS format_custom_field_delimiter=' :: ',
         format_custom_row_after_delimiter=' ;;\n',
         format_custom_escaping_rule='CSV'"

echo
echo "== 5. A .gz custom-delimited file decompresses transparently =="
clickhouse local -q "
SELECT count() FROM file('orders.txt.gz', CustomSeparatedWithNames)
SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"

echo
echo "== 6. Perf: group the ~112 MB, 3,000,000-row orders_large.txt (best-of-3, warm) =="
Q="SELECT country, count() AS orders, round(sum(revenue),2) AS revenue FROM file('orders_large.txt', CustomSeparatedWithNames) GROUP BY country ORDER BY revenue DESC SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_custom_time.txt
  echo "run $i: $(grep real /tmp/_custom_time.txt)"
done
clickhouse local -q "SELECT country, count() AS orders, round(sum(revenue),2) AS revenue FROM file('orders_large.txt', CustomSeparatedWithNames) GROUP BY country ORDER BY revenue DESC LIMIT 5 SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"
