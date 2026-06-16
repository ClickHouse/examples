#!/usr/bin/env bash
# The exact commands from the article "How to read an Avro file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 5 rows (schema read from the file) =="
clickhouse local -q "SELECT * FROM file('events.avro') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. See the schema without declaring one (DESCRIBE reads the embedded schema) =="
clickhouse local -q "DESCRIBE file('events.avro') FORMAT PrettyCompact"

echo
echo "== 3. Filter, aggregate, group by directly on the Avro file =="
clickhouse local -q "
SELECT country,
       count() AS events,
       round(sum(revenue), 2) AS revenue,
       round(avg(quantity), 2) AS avg_qty
FROM file('events.avro')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 4. Logical types round-trip: dates and timestamps come back typed =="
clickhouse local -q "
SELECT event_date, toTypeName(event_date) AS date_type,
       event_time, toTypeName(event_time) AS time_type
FROM file('events.avro') LIMIT 3 FORMAT PrettyCompact"

echo
echo "== 5. Perf: aggregate the 3M-row events_large.avro (best-of-3, warm) =="
Q="SELECT country, count(), round(sum(revenue),2), round(avg(quantity),3) FROM file('events_large.avro') WHERE event_type = 'purchase' GROUP BY country ORDER BY 3 DESC FORMAT Null"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
