#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to ORC".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> ORC in one line =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.orc' TRUNCATE FORMAT ORC"
echo "wrote events.orc"

echo
echo "== 2. Schema inferred from the CSV, types carried into ORC =="
echo "-- CSV (source):"
clickhouse local -q "DESCRIBE file('events.csv')"
echo "-- ORC (result):"
clickhouse local -q "DESCRIBE file('events.orc')"

echo
echo "== 3. Read the ORC back, or aggregate on it directly =="
clickhouse local -q "SELECT * FROM file('events.orc') LIMIT 5"
clickhouse local -q "SELECT count() FROM file('events.orc')"

echo
echo "== 4. Pin the types on conversion (note ORC stores signed ints + Date32) =="
clickhouse local -q "
SELECT * FROM file('events.csv', 'CSVWithNames',
  'event_date Date, event_id UInt32, country String, action String, amount Float64, quantity UInt8')
INTO OUTFILE 'events_typed.orc' TRUNCATE FORMAT ORC"
clickhouse local -q "DESCRIBE file('events_typed.orc')"

echo
echo "== 5. Choose the ORC compression codec =="
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.orc'      TRUNCATE FORMAT ORC"
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large_zstd.orc' TRUNCATE FORMAT ORC SETTINGS output_format_orc_compression_method='zstd'"
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large_none.orc' TRUNCATE FORMAT ORC SETTINGS output_format_orc_compression_method='none'"
clickhouse local -q "
SELECT name, formatReadableSize(total_bytes) AS size FROM (
  SELECT 'events_large.csv'               AS name, $(stat -f%z events_large.csv)       AS total_bytes
  UNION ALL SELECT 'events_large.orc (lz4 default)', $(stat -f%z events_large.orc)
  UNION ALL SELECT 'events_large_zstd.orc',          $(stat -f%z events_large_zstd.orc)
  UNION ALL SELECT 'events_large_none.orc',          $(stat -f%z events_large_none.orc)
) ORDER BY total_bytes DESC"

echo
echo "== 6. Conversion throughput: 3M rows / ~123 MB CSV -> ORC (best-of-3, warm) =="
CONV="SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.orc' TRUNCATE FORMAT ORC"
clickhouse local -q "$CONV" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CONV" > /dev/null 2> /tmp/_orc_time.txt
  echo "run $i: $(grep real /tmp/_orc_time.txt)"
done
