#!/usr/bin/env bash
# The exact commands from the article "How to read a Feather file".
# Run ./generate.sh first to create the sample data in ./data/.
# Feather IS the Arrow IPC file format -> read it with FORMAT Arrow.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 10 rows (.feather auto-detected as Arrow) =="
clickhouse local -q "SELECT * FROM file('events.feather') LIMIT 10 FORMAT PrettyCompact"

echo
echo "== 2. See the schema without declaring one =="
clickhouse local -q "DESCRIBE file('events.feather') FORMAT PrettyCompact"

echo
echo "== 3. Be explicit: FORMAT Arrow reads a Feather file =="
clickhouse local -q "SELECT count() FROM file('events.feather', 'Arrow')"

echo
echo "== 4. Filter, aggregate, group by, straight on the file =="
clickhouse local -q "
SELECT country,
       count() AS events,
       round(sum(revenue), 2) AS revenue,
       round(avg(quantity), 3) AS avg_qty
FROM file('events.feather')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 5. Gotcha: legacy Feather V1 (FEA1) is NOT the Arrow IPC format =="
clickhouse local -q "SELECT * FROM file('events_v1.feather', 'Arrow')" 2>&1 | head -3 || true

echo
echo "== 6. Convert Feather -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.feather') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 7. Perf: aggregate the 3M-row events_large.feather (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.feather') WHERE event_type='purchase' GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_feather_time.txt
  echo "run $i: $(grep real /tmp/_feather_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
