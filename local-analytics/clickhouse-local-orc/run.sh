#!/usr/bin/env bash
# The exact commands from the article "How to read an ORC file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows (schema auto-detected from the ORC footer) =="
clickhouse local -q "SELECT * FROM file('events.orc') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred schema, no CREATE TABLE =="
clickhouse local -q "DESCRIBE file('events.orc') FORMAT PrettyCompact"

echo
echo "== 3. Filter, aggregate, group by directly on the ORC file =="
clickhouse local -q "
SELECT country,
       count() AS events,
       round(sum(revenue), 2) AS revenue,
       round(avg(quantity), 3) AS avg_qty
FROM file('events.orc')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 4. Columnar read: query touches two columns, ORC reads only those =="
clickhouse local -q "
SELECT country, round(sum(revenue), 2) AS rev
FROM file('events_large.orc')
GROUP BY country
ORDER BY rev DESC
LIMIT 5
FORMAT PrettyCompact"

echo
echo "== 5. Override the inferred structure when you need to =="
clickhouse local -q "
SELECT country, count() AS events
FROM file('events.orc', 'ORC', 'country String, revenue Float64')
GROUP BY country ORDER BY country
FORMAT PrettyCompact"

echo
echo "== 6. Read a gzipped ORC transparently (.orc.gz) =="
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.orc.gz' TRUNCATE FORMAT ORC"
clickhouse local -q "SELECT count() FROM file('events.orc.gz') FORMAT PrettyCompact"

echo
echo "== 7. Perf: aggregate the 3M-row, ~28 MB events_large.orc (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.orc') WHERE event_type='purchase' GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_orc_time.txt
  echo "run $i: $(grep real /tmp/_orc_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
