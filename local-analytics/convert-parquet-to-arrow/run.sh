#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to Arrow".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> Arrow in one line =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.arrow' TRUNCATE FORMAT Arrow"
ls -la events.arrow

echo
echo "== 2. Schemas match: Parquet types carry into Arrow unchanged =="
echo "-- Parquet:"
clickhouse local -q "DESCRIBE file('events.parquet')"
echo "-- Arrow:"
clickhouse local -q "DESCRIBE file('events.arrow')"

echo
echo "== 3. Read the Arrow file back =="
clickhouse local -q "SELECT * FROM file('events.arrow') LIMIT 5"

echo
echo "== 4. .feather is the same Arrow IPC format =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.feather' TRUNCATE FORMAT Arrow"
clickhouse local -q "SELECT count() FROM file('events.feather')"

echo
echo "== 5. Compress the Arrow output (zstd) to shrink the file =="
clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large_zstd.arrow' TRUNCATE FORMAT Arrow SETTINGS output_format_arrow_compression_method='zstd'"
echo "-- sizes (Parquet input vs uncompressed Arrow vs zstd Arrow):"
clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.arrow' TRUNCATE FORMAT Arrow"
ls -la events_large.parquet events_large.arrow events_large_zstd.arrow

echo
echo "== 6. Row + value parity after the round trip =="
clickhouse local -q "SELECT (SELECT count() FROM file('events_large.parquet')) AS parquet_rows, (SELECT count() FROM file('events_large.arrow')) AS arrow_rows"

echo
echo "== 7. Perf: convert 3,000,000 rows Parquet -> Arrow (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.arrow' TRUNCATE FORMAT Arrow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_arrow_time.txt
  echo "run $i: $(grep real /tmp/_arrow_time.txt)"
done
