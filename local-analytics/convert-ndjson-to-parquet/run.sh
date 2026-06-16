#!/usr/bin/env bash
# The exact commands from the article "How to convert NDJSON to Parquet".
# NDJSON and JSONL are the same format. Run ./generate.sh first.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert NDJSON -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 2. Schema inferred from the NDJSON (nested object -> Tuple, array -> Array) =="
clickhouse local -q "DESCRIBE file('events.ndjson')"

echo
echo "== 3. Same schema carried into the Parquet file (nesting preserved) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 4. Read the nested columns back out of the Parquet =="
clickhouse local -q "SELECT event_id, user.country, user.plan, items FROM file('events.parquet') ORDER BY event_id LIMIT 5"

echo
echo "== 5. Inspect the Parquet footer: nested types flatten to leaf columns, default ZSTD =="
clickhouse local -q "SELECT num_columns, num_rows, num_row_groups, format_version, columns.name, columns.compression FROM file('events.parquet', ParquetMetadata) FORMAT Vertical"

echo
echo "== 6. Choose the compression codec (default is zstd) =="
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events_snappy.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='snappy'"
ls -la events.parquet events_snappy.parquet | awk '{print $5"\t"$NF}'

echo
echo "== 7. Size: 1M-row, ~140 MB events_large.ndjson -> Parquet =="
clickhouse local -q "SELECT * FROM file('events_large.ndjson') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
ls -la events_large.ndjson events_large.parquet | awk '{print $5"\t"$NF}'

echo
echo "== 8. Conversion throughput (best-of-3, warm OS page cache) =="
Q="SELECT * FROM file('events_large.ndjson') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "$Q" > /dev/null 2>&1   # warm the cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_ndjson_parquet_time.txt
  echo "run $i: $(grep real /tmp/_ndjson_parquet_time.txt)"
done
