#!/usr/bin/env bash
# The exact commands from the article "How to query a mysqldump file without importing".
# Run ./generate.sh first to create the sample dumps in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. List the tables in the dump =="
clickhouse local -q "
SELECT extract(line, 'INSERT INTO .(\w+).') AS table_name
FROM file('shop.sql', LineAsString)
WHERE line LIKE 'INSERT INTO%'"

echo
echo "== 2. See the inferred schema for one table (from the CREATE TABLE in the dump) =="
clickhouse local -q "
DESCRIBE file('shop.sql', MySQLDump)
SETTINGS input_format_mysql_dump_table_name = 'orders'"

echo
echo "== 3. Read the rows of the selected table =="
clickhouse local -q "
SELECT * FROM file('shop.sql', MySQLDump)
SETTINGS input_format_mysql_dump_table_name = 'orders'"

echo
echo "== 4. Pick a different table by name =="
clickhouse local -q "
SELECT * FROM file('shop.sql', MySQLDump)
SETTINGS input_format_mysql_dump_table_name = 'customers'"

echo
echo "== 5. Aggregate directly on the dump, no import step =="
clickhouse local -q "
SELECT product, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('shop.sql', MySQLDump)
GROUP BY product
ORDER BY revenue DESC
SETTINGS input_format_mysql_dump_table_name = 'orders'"

echo
echo "== 6. Default table (first INSERT in the file) when no name is given =="
clickhouse local -q "
SELECT count() FROM file('shop.sql', MySQLDump)"

echo
echo "== 7. Perf: GROUP BY over the 2,000,000-row events dump (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.sql', MySQLDump) GROUP BY country ORDER BY revenue DESC LIMIT 5 SETTINGS input_format_mysql_dump_table_name='events'"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_mysqldump_time.txt
  echo "run $i: $(grep real /tmp/_mysqldump_time.txt)"
done
clickhouse local -q "$Q"
