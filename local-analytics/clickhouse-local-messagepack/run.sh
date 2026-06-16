#!/usr/bin/env bash
# The exact commands from the article "How to read a MessagePack file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

SCHEMA='id UInt64, country String, event_type String, revenue Float64, quantity UInt8'

echo "== 1. Read fails without an explicit structure (MsgPack carries no schema) =="
clickhouse local -q "SELECT * FROM file('events.msgpack') LIMIT 3" 2>&1 | head -3 || true

echo
echo "== 2. Read with an explicit structure (format + schema as 2nd and 3rd args) =="
clickhouse local -q "
SELECT * FROM file('events.msgpack', MsgPack, '$SCHEMA')
LIMIT 5
FORMAT PrettyCompact"

echo
echo "== 3. Filter, aggregate, group by — full SQL on the file =="
clickhouse local -q "
SELECT country,
       count() AS purchases,
       round(sum(revenue), 2) AS revenue,
       round(avg(quantity), 3) AS avg_qty
FROM file('events.msgpack', MsgPack, '$SCHEMA')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 4. Compressed MsgPack (.msgpack.gz) reads transparently =="
clickhouse local -q "
SELECT count(), round(sum(revenue), 2)
FROM file('events.msgpack.gz', MsgPack, '$SCHEMA')
FORMAT PrettyCompact"

echo
echo "== 5. Perf: aggregate the 3M-row events_large.msgpack (best-of-3, warm) =="
Q="SELECT country, count(), round(sum(revenue),2), round(avg(quantity),3) FROM file('events_large.msgpack', MsgPack, '$SCHEMA') WHERE event_type = 'purchase' GROUP BY country ORDER BY 3 DESC FORMAT Null"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_msgpack_time.txt
  echo "run $i: $(grep real /tmp/_msgpack_time.txt)"
done
