#!/usr/bin/env bash
# The exact commands from the article "Convert Avro to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Avro -> CSV in one line =="
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
head -7 events.csv

echo
echo "== 2. Inspect the schema Avro carried (note ts is a raw int, the Tuple is named) =="
clickhouse local -q "DESCRIBE file('events.avro')"

echo
echo "== 3. Flatten cleanly: Tuple -> columns, Array -> joined string, int -> DateTime =="
clickhouse local -q "
SELECT
  event_id,
  toDateTime(ts)               AS ts,
  event_type,
  country,
  amount,
  user_info.1                  AS user_id,
  user_info.2                  AS sessions,
  arrayStringConcat(tags, '|') AS tags
FROM file('events.avro')
INTO OUTFILE 'events_flat.csv' TRUNCATE FORMAT CSVWithNames
"
head -7 events_flat.csv

echo
echo "== 4. Perf: convert the 3M-row, ~81 MB events_large.avro (best-of-3, warm) =="
Q="SELECT event_id, toDateTime(ts) AS ts, event_type, country, amount, user_info.1 AS user_id, user_info.2 AS sessions, arrayStringConcat(tags,'|') AS tags FROM file('events_large.avro') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_avro_csv_time.txt
  echo "run $i: $(grep real /tmp/_avro_csv_time.txt)"
done
echo "rows written: $(clickhouse local -q "SELECT count() FROM file('events_large.csv')")"
ls -lh events_large.avro events_large.csv | awk '{print $5, $9}'
