#!/usr/bin/env bash
# The exact commands from the article "How to read a RowBinary file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Self-describing: RowBinaryWithNamesAndTypes carries its own schema =="
clickhouse local -q "SELECT * FROM file('events.rowbinary', 'RowBinaryWithNamesAndTypes') LIMIT 3 FORMAT PrettyCompact"

echo
echo "== 2. DESCRIBE the self-describing file (no CREATE TABLE) =="
clickhouse local -q "DESCRIBE file('events.rowbinary', 'RowBinaryWithNamesAndTypes') FORMAT PrettyCompact"

echo
echo "== 3. Aggregate directly on the RowBinary file =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),2) AS avg_qty
FROM file('events.rowbinary', 'RowBinaryWithNamesAndTypes')
GROUP BY country ORDER BY revenue DESC FORMAT PrettyCompact"

echo
echo "== 4. Plain RowBinary has NO header: schema inference fails =="
clickhouse local -q "SELECT * FROM file('events_plain.rowbinary', 'RowBinary') LIMIT 1" 2>&1 | head -1 || true

echo
echo "== 5. Plain RowBinary: supply the structure yourself (3rd argument) =="
clickhouse local -q "
SELECT * FROM file('events_plain.rowbinary', 'RowBinary',
  'event_time DateTime, user_id UInt32, country String, event_type String, revenue Float64, quantity UInt8')
LIMIT 3 FORMAT PrettyCompact"

echo
echo "== 6. The safety net: WithNamesAndTypes validates the types you pass =="
clickhouse local -q "
SELECT * FROM file('events.rowbinary', 'RowBinaryWithNamesAndTypes',
  'event_time DateTime, user_id String, country String, event_type String, revenue Float64, quantity UInt8')
LIMIT 1" 2>&1 | head -1 || true

echo
echo "== 7. Perf: aggregate the 3M-row events_large.rowbinary (best-of-3, warm) =="
Q="SELECT country, count(), round(sum(revenue),2), round(avg(quantity),3) FROM file('events_large.rowbinary','RowBinaryWithNamesAndTypes') GROUP BY country ORDER BY 2 DESC FORMAT Null"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_rb_time.txt
  echo "run $i: $(grep real /tmp/_rb_time.txt)"
done
