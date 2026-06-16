#!/usr/bin/env bash
# The exact commands from the article "How to convert Avro to Parquet".
# Run ./generate.sh first to create the sample Avro files in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Avro -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
echo "wrote events.parquet"

echo
echo "== 2. The schema Avro carried, now in the Parquet file =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Read it back to confirm the data round-tripped =="
clickhouse local -q "SELECT * FROM file('events.parquet') ORDER BY event_id LIMIT 5"

echo
echo "== 4. Pick the compression codec (default is zstd); compare on the 3M-row file =="
for c in none snappy zstd; do
  clickhouse local -q "
  SELECT * FROM file('events_large.avro')
  INTO OUTFILE 'events_large.$c.parquet' TRUNCATE FORMAT Parquet
  SETTINGS output_format_parquet_compression_method = '$c'"
  printf "  %-7s %s bytes\n" "$c" "$(stat -f %z events_large.$c.parquet)"
done
rm -f events_large.none.parquet events_large.snappy.parquet events_large.zstd.parquet

echo
echo "== 5. Inspect the Parquet footer (row groups, compression) =="
clickhouse local -q "
SELECT num_rows, num_row_groups, format_version
FROM file('events.parquet', ParquetMetadata)
FORMAT Vertical
"

echo
echo "== 6. Conversion throughput: 3,000,000-row events_large.avro -> Parquet (best-of-3, warm) =="
CMD="SELECT * FROM file('events_large.avro') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "$CMD"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
echo "input  events_large.avro:     $(ls -l events_large.avro | awk '{print $5}') bytes"
echo "output events_large.parquet:  $(ls -l events_large.parquet | awk '{print $5}') bytes"
clickhouse local -q "SELECT count() AS rows FROM file('events_large.parquet')"
