#!/usr/bin/env bash
# The exact commands from the article "How to convert JSONL to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert JSONL -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
echo "wrote events.parquet; row count:"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 2. Schema inferred from JSONL (types per column) =="
clickhouse local -q "DESCRIBE file('events.jsonl')"

echo
echo "== 3. Schema carried into the Parquet file (ts -> DateTime64, nested device -> Tuple/struct) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 4. Nested JSON survives as a real Parquet struct =="
clickhouse local -q "SELECT event_id, device.os AS os, device.ver AS ver, amount FROM file('events.parquet') ORDER BY event_id LIMIT 5 FORMAT PrettyCompactMonoBlock"

echo
echo "== 5. Pick the compression codec explicitly (default is snappy; zstd packs smaller) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events_zstd.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd'"
echo "wrote events_zstd.parquet"

echo
echo "== 6. Inspect the Parquet footer (row groups + compressed size) =="
clickhouse local -q "SELECT * FROM file('events_large.jsonl') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT num_rows, num_row_groups, total_compressed_size, total_uncompressed_size FROM file('events_large.parquet', ParquetMetadata) FORMAT Vertical"

echo
echo "== 7. Size: 137 MB of JSONL -> a much smaller, typed Parquet file =="
clickhouse local -q "SELECT * FROM file('events_large.jsonl') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
stat -f '%z bytes  %N' events_large.jsonl events_large.parquet 2>/dev/null || ls -l events_large.jsonl events_large.parquet

echo
echo "== 8. Perf: convert the 1,000,000-row, ~137 MB events_large.jsonl (best-of-3, warm) =="
CMD="SELECT * FROM file('events_large.jsonl') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "$CMD" > /dev/null 2>&1   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_jsonl_time.txt
  echo "run $i: $(grep real /tmp/_jsonl_time.txt)"
done
