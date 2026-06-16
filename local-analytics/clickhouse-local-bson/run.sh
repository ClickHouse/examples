#!/usr/bin/env bash
# The exact commands from the article "How to query a BSON file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows (schema auto-detected from BSON) =="
clickhouse local -q "SELECT * FROM file('events.bson') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred schema (no CREATE TABLE) =="
clickhouse local -q "DESCRIBE file('events.bson') FORMAT PrettyCompact"

echo
echo "== 3. Reach into the nested geo sub-document by key =="
clickhouse local -q "
SELECT _id, user, event, geo.country AS country, geo.sessions AS sessions
FROM file('events.bson')
LIMIT 5
FORMAT PrettyCompact"

echo
echo "== 4. Filter, group and aggregate directly on the BSON =="
clickhouse local -q "
SELECT geo.country AS country, count() AS events, round(sum(amount), 2) AS amount
FROM file('events.bson')
WHERE event = 'purchase'
GROUP BY country
ORDER BY amount DESC
FORMAT PrettyCompact"

echo
echo "== 5. Convert BSON -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.bson') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 6. Perf: group-by over the 1.3M-row, ~140 MB events_large.bson (best-of-3, warm) =="
Q="SELECT geo.country AS country, count() AS events, round(sum(amount),2) AS amount FROM file('events_large.bson') WHERE event='purchase' GROUP BY country ORDER BY amount DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_bson_time.txt
  echo "run $i: $(grep real /tmp/_bson_time.txt)"
done
clickhouse local -q "$Q"
