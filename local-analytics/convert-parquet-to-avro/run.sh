#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to Avro".
# Run ./generate.sh first to create the sample Parquet files in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> Avro in one line =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.avro' TRUNCATE FORMAT Avro"
clickhouse local -q "SELECT count() AS rows FROM file('events.avro')"

echo
echo "== 2. Source Parquet schema (columnar, typed) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Avro schema after conversion (note the integer widening) =="
clickhouse local -q "DESCRIBE file('events.avro')"

echo
echo "== 4. Read the Avro back: nested tuple became a nested Avro record =="
clickhouse local -q "SELECT * FROM file('events.avro') ORDER BY event_id LIMIT 3 FORMAT JSONEachRow"

echo
echo "== 5. Access the nested record fields =="
clickhouse local -q "SELECT event_id, device.1 AS device_type, device.2 AS is_even FROM file('events.avro') ORDER BY event_id LIMIT 3"

echo
echo "== 6. Smaller Avro with the deflate codec =="
clickhouse local -q "SET output_format_avro_codec='deflate'; SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.avro' TRUNCATE FORMAT Avro"
ls -la events_large.parquet events_large.avro

echo
echo "== 7. Perf: convert the 3M-row events_large.parquet -> Avro (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.avro' TRUNCATE FORMAT Avro"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
clickhouse local -q "SELECT count() FROM file('events_large.avro')"
