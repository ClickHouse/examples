#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to JSONL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> JSONL in one line =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
echo "wrote events.jsonl; first 3 lines:"
head -3 events.jsonl

echo
echo "== 2. The CSV schema, auto-inferred (carried into JSONL types) =="
clickhouse local -q "DESCRIBE file('events.csv')"

echo
echo "== 3. Round-trip: read the JSONL straight back, no schema needed =="
clickhouse local -q "SELECT country, count() AS events, round(sum(amount),2) AS amount FROM file('events.jsonl') GROUP BY country ORDER BY amount DESC"

echo
echo "== 4. Keep 64-bit integers JS-safe by quoting them =="
clickhouse local -q "SELECT * FROM file('events.csv') LIMIT 2 FORMAT JSONEachRow SETTINGS output_format_json_quote_64bit_integers=1"

echo
echo "== 5. Convert and gzip in the same command (.jsonl.gz auto-detected) =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"
echo "wrote events.jsonl.gz; read it back transparently:"
clickhouse local -q "SELECT count() FROM file('events.jsonl.gz')"

echo
echo "== 6. Reverse direction: JSONL -> CSV =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_roundtrip.csv' TRUNCATE FORMAT CSVWithNames"
head -3 events_roundtrip.csv

echo
echo "== 7. Throughput: convert the 3M-row, ~120 MB events_large.csv (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow" > /dev/null  # warm cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow" > /dev/null 2> /tmp/_jsonl_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_time.txt)"
done
echo "rows in output:"
clickhouse local -q "SELECT count() FROM file('events_large.jsonl')"
ls -la events_large.jsonl
