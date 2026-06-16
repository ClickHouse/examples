#!/usr/bin/env bash
# The exact commands from the article "How to convert JSON to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. The inferred schema: note the nested 'user' Tuple and 'amounts' Array =="
clickhouse local -q "DESCRIBE file('events.jsonl', JSONEachRow)"

echo
echo "== 2. Naive SELECT * -> CSV: the nested 'user' object splits into unlabelled =="
echo "==    columns, so the header (5 cols) no longer lines up with the rows (6).  =="
clickhouse local -q "SELECT * FROM file('events.jsonl', JSONEachRow) INTO OUTFILE 'naive.csv' TRUNCATE FORMAT CSVWithNames"
head -3 naive.csv

echo
echo "== 3. Flatten nested fields explicitly, then write CSV =="
clickhouse local -q "
SELECT
  event_id,
  event_type,
  ts,
  user.country AS user_country,
  user.plan    AS user_plan,
  amounts[1]   AS amount_primary,
  arrayStringConcat(arrayMap(x -> toString(x), amounts), ';') AS amounts_list
FROM file('events.jsonl', JSONEachRow)
INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames
"
head -5 events.csv

echo
echo "== 4. Round-trip: read the CSV back, every column is flat and typed =="
clickhouse local -q "DESCRIBE file('events.csv', CSVWithNames)"

echo
echo "== 5. chDB Python equivalent (same flattening SELECT, written to a file) =="
python3 ../run.py

echo
echo "== 6. Perf: convert the 1M-row, ~125 MB events_large.jsonl -> CSV (best-of-3, warm) =="
CONV="SELECT event_id, event_type, ts, user.country AS user_country, user.plan AS user_plan, amounts[1] AS amount_primary, arrayStringConcat(arrayMap(x -> toString(x), amounts), ';') AS amounts_list FROM file('events_large.jsonl', JSONEachRow) INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$CONV" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CONV" > /dev/null 2> /tmp/_json2csv_time.txt
  echo "run $i: $(grep real /tmp/_json2csv_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('events_large.csv', CSVWithNames)"
