#!/usr/bin/env bash
# The exact commands from the article "How to convert MessagePack to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. MsgPack read needs an explicit structure (this is the gotcha) =="
echo "-- without a structure, schema cannot be extracted:"
clickhouse local -q "SELECT * FROM file('orders.msgpack') LIMIT 3" 2>&1 | head -3 || true

echo
echo "== 2. Convert MsgPack -> CSV in one line (supply the structure, write CSVWithNames) =="
clickhouse local -q "
SELECT * FROM file('orders.msgpack', MsgPack,
  'order_date Date, order_id UInt64, country String, product String, revenue Float64, quantity UInt8')
INTO OUTFILE 'orders.csv' TRUNCATE FORMAT CSVWithNames
"
echo "-- first rows of the resulting CSV:"
head -6 orders.csv

echo
echo "== 3. Confirm the round-trip: query the CSV back =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('orders.csv')
GROUP BY country
ORDER BY revenue DESC
"

echo
echo "== 4. Convert MsgPack -> CSV (3,000,000 rows), best-of-3 warm =="
CMD="SELECT * FROM file('orders_large.msgpack', MsgPack, 'order_date Date, order_id UInt64, country String, product String, revenue Float64, quantity UInt8') INTO OUTFILE 'orders_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$CMD" > /dev/null   # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_mp_time.txt
  echo "run $i: $(grep real /tmp/_mp_time.txt)"
done
echo "-- output row count and size:"
clickhouse local -q "SELECT count() FROM file('orders_large.csv', CSVWithNames)"
ls -la orders_large.csv
