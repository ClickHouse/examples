#!/usr/bin/env bash
# The exact commands from the article "How to convert Arrow to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Arrow IPC -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() AS rows FROM file('events.parquet')"

echo
echo "== 2. Types carried straight from Arrow into Parquet (no Nullable, no re-parsing) =="
clickhouse local -q "DESCRIBE file('events.arrow')"
echo "-- and the Parquet that came out --"
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Streaming Arrow IPC needs the ArrowStream format on read =="
echo "-- this FAILS: a stream file is not an Arrow 'file' --"
clickhouse local -q "SELECT count() FROM file('events_stream.arrow')" 2>&1 | head -2 || true
echo "-- this WORKS: name the framing explicitly --"
clickhouse local -q "SELECT * FROM file('events_stream.arrow', 'ArrowStream') INTO OUTFILE 'events_stream.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() AS rows FROM file('events_stream.parquet')"

echo
echo "== 4. Inspect the Parquet footer: compression and row count =="
clickhouse local -q "SELECT num_rows, num_columns, num_row_groups, format_version FROM file('events.parquet', ParquetMetadata) FORMAT Vertical"
clickhouse local -q "SELECT tupleElement(arrayJoin(columns), 'name') AS column, tupleElement(arrayJoin(columns), 'compression') AS compression FROM file('events.parquet', ParquetMetadata)"

echo
echo "== 5. Pick a different codec (default is zstd); here, snappy =="
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events_snappy.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='snappy'"
clickhouse local -q "SELECT DISTINCT tupleElement(arrayJoin(columns), 'compression') AS compression FROM file('events_snappy.parquet', ParquetMetadata)"

echo
echo "== 6. Query the Arrow file directly without converting first =="
clickhouse local -q "
SELECT event_type, count() AS events, round(sum(amount), 2) AS amount
FROM file('events.arrow')
GROUP BY event_type
ORDER BY amount DESC
"

echo
echo "== 7. Perf: convert the ~46 MB, 3M-row events_large.arrow -> Parquet (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.arrow') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"  # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.arrow') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet" 2> /tmp/_arrow_time.txt
  echo "run $i: $(grep real /tmp/_arrow_time.txt)"
done
echo "-- input vs output size --"
ls -la events_large.arrow events_large.parquet | awk '{print $5"\t"$9}'
clickhouse local -q "SELECT count() AS rows FROM file('events_large.parquet')"
