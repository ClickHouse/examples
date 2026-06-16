#!/usr/bin/env bash
# The exact commands from the article "How to query an NDJSON file with SQL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first 5 rows (.ndjson -> JSONEachRow auto-detected) =="
clickhouse local -q "SELECT * FROM file('events.ndjson') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred schema (no CREATE TABLE) =="
clickhouse local -q "DESCRIBE file('events.ndjson') FORMAT PrettyCompact"

echo
echo "== 3. Aggregate directly on the NDJSON, no import step =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount), 2) AS amount, round(avg(quantity), 2) AS avg_qty
FROM file('events.ndjson')
GROUP BY country
ORDER BY amount DESC
FORMAT PrettyCompact"

echo
echo "== 4. Same data, .jsonl extension, explicit JSONEachRow format =="
cp events.ndjson events.jsonl
clickhouse local -q "SELECT count() FROM file('events.jsonl', JSONEachRow)"
rm -f events.jsonl

echo
echo "== 5. Read a gzipped NDJSON transparently (.ndjson.gz) =="
clickhouse local -q "SELECT country, count() FROM file('events.ndjson.gz') GROUP BY country ORDER BY country FORMAT PrettyCompact"

echo
echo "== 6. Convert NDJSON -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 7. Perf: aggregate the 3M-row events_large.ndjson (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(amount),2) AS amount, round(avg(quantity),3) AS avg_qty FROM file('events_large.ndjson') WHERE event_type = 'purchase' GROUP BY country ORDER BY amount DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_ndjson_time.txt
  echo "run $i: $(grep real /tmp/_ndjson_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
