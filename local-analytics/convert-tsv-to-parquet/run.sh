#!/usr/bin/env bash
# The exact commands from the article "How to convert TSV to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# Portable byte-size helper (macOS `stat -f%z`, GNU `stat -c%s`).
fsize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

echo "== 1. Convert TSV -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
echo "events.tsv     $(fsize events.tsv) bytes"
echo "events.parquet $(fsize events.parquet) bytes"

echo
echo "== 2. The types were inferred from the TSV and carried into Parquet =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Read the Parquet back to confirm it is correct =="
clickhouse local -q "SELECT * FROM file('events.parquet') ORDER BY event_id LIMIT 5"

echo
echo "== 4. Lock the schema instead of inferring (keep event_id a UInt32, etc.) =="
clickhouse local -q "
SELECT * FROM file('events.tsv', 'TSVWithNames',
  'event_date Date, event_id UInt32, country String, action String, amount Float64, sessions UInt8')
INTO OUTFILE 'events.typed.parquet' TRUNCATE FORMAT Parquet
"
clickhouse local -q "DESCRIBE file('events.typed.parquet')"

echo
echo "== 5. Compression: ClickHouse defaults to zstd; compare codecs on the 3M-row file =="
for codec in none lz4 zstd; do
  clickhouse local -q "
  SELECT * FROM file('events_large.tsv')
  INTO OUTFILE 'events_large.$codec.parquet' TRUNCATE FORMAT Parquet
  SETTINGS output_format_parquet_compression_method = '$codec'
  "
  printf "  %-5s %s bytes\n" "$codec" "$(fsize events_large.$codec.parquet)"
done
echo "  (source events_large.tsv: $(fsize events_large.tsv) bytes)"

echo
echo "== 6. Inspect the Parquet footer (rows, row groups, per-column codec) with ParquetMetadata =="
clickhouse local -q "
SELECT num_rows, num_row_groups,
       arrayDistinct(arrayMap(c -> c.compression, columns)) AS codecs
FROM file('events_large.zstd.parquet', ParquetMetadata)
FORMAT Vertical
"

echo
echo "== 7. Perf: convert the 3M-row, ~111 MB events_large.tsv -> Parquet (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.tsv') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet" # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.tsv') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet" 2> /tmp/_tsv_time.txt
  echo "run $i: $(grep real /tmp/_tsv_time.txt)"
done
clickhouse local -q "SELECT count() FROM file('events_large.parquet')"
