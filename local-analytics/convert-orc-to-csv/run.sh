#!/usr/bin/env bash
# The exact commands from the article "How to convert ORC to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert ORC -> CSV in one line (header included) =="
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
head -4 events.csv

echo
echo "== 2. Inspect the schema ClickHouse infers from the ORC footer =="
clickhouse local -q "DESCRIBE file('events.orc')"

echo
echo "== 3. The gotcha: a typed Map column has no CSV shape. Flatten it into scalar columns =="
clickhouse local -q "
SELECT
  event_time,
  event_id,
  country,
  action,
  amount,
  tags['utm_source'] AS utm_source,
  tags['device']     AS device
FROM file('events.orc')
INTO OUTFILE 'events_flat.csv' TRUNCATE FORMAT CSVWithNames"
head -4 events_flat.csv

echo
echo "== 4. Option: tidy the timestamp and keep the map as a JSON string =="
clickhouse local -q "
SELECT
  formatDateTime(event_time, '%Y-%m-%d %H:%i:%S') AS event_time,
  event_id, country, action, amount,
  toJSONString(tags) AS tags_json
FROM file('events.orc')
ORDER BY event_id LIMIT 3
FORMAT CSVWithNames"

echo
echo "== 5. Verify the conversion round-trips (row counts match) =="
echo -n "orc rows: "; clickhouse local -q "SELECT count() FROM file('events.orc')"
echo -n "csv rows: "; clickhouse local -q "SELECT count() FROM file('events.csv')"

echo
echo "== 6. Conversion throughput: 3,000,000-row events_large.orc -> CSV (best-of-3, warm) =="
Q="SELECT event_time, event_id, country, action, amount, tags['utm_source'] AS utm_source, tags['device'] AS device FROM file('events_large.orc') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_orc_csv_time.txt
  echo "run $i: $(grep real /tmp/_orc_csv_time.txt)"
done
echo -n "output CSV size: "; du -h events_large.csv | cut -f1
echo -n "csv rows: "; clickhouse local -q "SELECT count() FROM file('events_large.csv')"
