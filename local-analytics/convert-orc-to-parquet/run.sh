#!/usr/bin/env bash
# The exact commands from the article "How to convert ORC to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert ORC -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count() FROM file('events.parquet')"

echo
echo "== 2. The schema is inferred from the ORC footer and carried into Parquet =="
clickhouse local -q "DESCRIBE file('events.orc')"

echo
echo "== 3. Same types on the Parquet side, nested Map preserved (no flattening) =="
clickhouse local -q "DESCRIBE file('events.parquet')"
clickhouse local -q "SELECT event_date, event_id, country, event_type, amount, attrs FROM file('events.parquet') ORDER BY event_id LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 4. Pick the Parquet compression codec (the column-store knob converters hide) =="
clickhouse local -q "SELECT * FROM file('events_large.orc') INTO OUTFILE 'events_large_zstd.parquet'   TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd'"
clickhouse local -q "SELECT * FROM file('events_large.orc') INTO OUTFILE 'events_large_snappy.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='snappy'"
clickhouse local -q "SELECT * FROM file('events_large.orc') INTO OUTFILE 'events_large_none.parquet'   TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='none'"
echo "bytes  file"
stat -f '%z  %N' events_large.orc events_large_zstd.parquet events_large_snappy.parquet events_large_none.parquet 2>/dev/null \
  || stat -c '%s  %n' events_large.orc events_large_zstd.parquet events_large_snappy.parquet events_large_none.parquet

echo
echo "== 5. Inspect the Parquet footer without opening the data =="
clickhouse local -q "SELECT num_columns, num_rows, num_row_groups, format_version FROM file('events_large_zstd.parquet', ParquetMetadata) FORMAT Vertical"

echo
echo "== 6. Conversion throughput: 3,000,000-row events_large.orc (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.orc') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_orc_time.txt
  echo "run $i: $(grep real /tmp/_orc_time.txt)"
done
