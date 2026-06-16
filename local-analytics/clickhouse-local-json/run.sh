#!/usr/bin/env bash
# The exact commands from the article "How to query a JSON file with SQL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows of a JSON file (JSONEachRow) =="
clickhouse local -q "SELECT * FROM file('events.jsonl', JSONEachRow) LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. The same call reads a top-level JSON array =="
clickhouse local -q "SELECT count() FROM file('events.json', JSONEachRow)"

echo
echo "== 3. Inspect the inferred schema (nested object -> Tuple, array -> Array) =="
clickhouse local -q "DESCRIBE file('events.jsonl', JSONEachRow) FORMAT PrettyCompact"

echo
echo "== 4. Reach into a nested object with dot access =="
clickhouse local -q "
SELECT event_id, geo.country AS country, geo.city AS city
FROM file('events.jsonl', JSONEachRow)
LIMIT 5
FORMAT PrettyCompact"

echo
echo "== 5. Group by a nested field =="
clickhouse local -q "
SELECT geo.country AS country, count() AS events, round(sum(amount), 2) AS total
FROM file('events.jsonl', JSONEachRow)
GROUP BY country
ORDER BY total DESC
FORMAT PrettyCompact"

echo
echo "== 6. Explode an array column with arrayJoin =="
clickhouse local -q "
SELECT tag, count() AS events
FROM file('events.jsonl', JSONEachRow)
ARRAY JOIN tags AS tag
GROUP BY tag
ORDER BY events DESC
FORMAT PrettyCompact"

echo
echo "== 7. Read a gzipped JSONL transparently (.jsonl.gz) =="
clickhouse local -q "
SELECT event_type, count()
FROM file('events.jsonl.gz', JSONEachRow)
GROUP BY event_type
ORDER BY event_type
FORMAT PrettyCompact"

echo
echo "== 8. Perf: aggregate the 3M-row events_large.jsonl (best-of-3, warm) =="
Q="SELECT geo.country AS country, count() AS events, round(sum(amount),2) AS total FROM file('events_large.jsonl', JSONEachRow) GROUP BY country ORDER BY total DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_json_time.txt
  echo "run $i: $(grep real /tmp/_json_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
