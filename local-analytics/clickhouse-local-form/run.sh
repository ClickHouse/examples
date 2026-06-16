#!/usr/bin/env bash
# The exact commands from the article "Parse url-encoded / form data with SQL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Parse one form body into a row (keys become columns) =="
clickhouse local -q "SELECT * FROM file('payload.txt', Form) FORMAT Vertical"

echo
echo "== 2. See the inferred schema (every field is a String) =="
clickhouse local -q "DESCRIBE file('payload.txt', Form)"

echo
echo "== 3. Give fields real types so you can compute on them =="
clickhouse local -q "
SELECT event, user_id, plan, amount, country
FROM file('payload.txt', Form, 'event String, user_id UInt32, plan String, amount Decimal(10,2), country String')
FORMAT Vertical"

echo
echo "== 4. Percent-encoding is decoded; '+' is NOT turned into a space =="
clickhouse local -q "SELECT * FROM file('encoded.txt', Form) FORMAT Vertical"
echo "-- fix '+' yourself with replaceAll --"
clickhouse local -q "
SELECT replaceAll(name, '+', ' ') AS name, replaceAll(city, '+', ' ') AS city, note, amount
FROM file('encoded.txt', Form) FORMAT Vertical"

echo
echo "== 5. One row per file: glob a folder of webhook bodies =="
clickhouse local -q "
SELECT _file AS src, event, user_id, plan, amount
FROM file('hooks/*.txt', Form, 'event String, user_id UInt32, plan String, amount Decimal(10,2)')
ORDER BY user_id
FORMAT PrettyCompact"

echo
echo "== 6. Aggregate across all the form payloads =="
clickhouse local -q "
SELECT event, count() AS n, sum(amount) AS revenue
FROM file('hooks/*.txt', Form, 'event String, user_id UInt32, plan String, amount Decimal(10,2)')
GROUP BY event
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 7. Perf: aggregate 2000 one-body form files (best-of-3, warm) =="
Q="SELECT plan, count() AS n, sum(amount) AS revenue FROM file('perf/*.txt', Form, 'event String, user_id UInt32, plan String, amount Decimal(10,2), country String') GROUP BY plan ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_form_time.txt
  echo "run $i: $(grep real /tmp/_form_time.txt)"
done
clickhouse local -q "$Q FORMAT PrettyCompact"
