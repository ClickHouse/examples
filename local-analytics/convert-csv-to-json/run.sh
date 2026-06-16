#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> JSON, one object per line (JSONEachRow / NDJSON) =="
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.jsonl' TRUNCATE FORMAT JSONEachRow"
echo "first 3 lines of orders.jsonl:"
head -n 3 orders.jsonl

echo
echo "== 2. Convert CSV -> a single JSON array of objects (FORMAT JSON) =="
clickhouse local -q "SELECT * FROM file('orders.csv') LIMIT 2 FORMAT JSON"

echo
echo "== 3. Just the array, no meta/stats wrapper: JSONCompactEachRow per line =="
clickhouse local -q "SELECT * FROM file('orders.csv') LIMIT 2 FORMAT JSONCompactEachRow"

echo
echo "== 4. Types are carried from inference: numbers stay numbers, not strings =="
clickhouse local -q "DESCRIBE file('orders.csv')"
echo "-> in the JSON, order_id/quantity are bare ints, revenue is a float, no quotes:"
clickhouse local -q "SELECT * FROM file('orders.csv') LIMIT 1 FORMAT JSONEachRow"

echo
echo "== 5. Keep a column as a string when inference guesses wrong (e.g. zero-padded ids) =="
clickhouse local -q "
SELECT * FROM file('orders.csv', 'CSVWithNames',
  'order_date Date, order_id String, country String, product String, revenue Float64, quantity UInt8')
LIMIT 1 FORMAT JSONEachRow"

echo
echo "== 6. Conversion throughput: 2,000,000-row, ~84 MB CSV -> JSONEachRow (best-of-3, warm) =="
Q="SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" 2> /tmp/_csv2json_time.txt
  echo "run $i: $(grep real /tmp/_csv2json_time.txt)"
done
echo "input vs output size:"
ls -la orders_large.csv orders_large.jsonl
echo "row count in the JSONL output:"
clickhouse local -q "SELECT count() FROM file('orders_large.jsonl')"
