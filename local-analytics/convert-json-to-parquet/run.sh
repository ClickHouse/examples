#!/usr/bin/env bash
# The exact commands from the article "How to convert JSON to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert JSON -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('events.json') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
echo "wrote events.parquet"

echo
echo "== 2. Schema inferred from the JSON (note the nested geo object) =="
clickhouse local -q "DESCRIBE file('events.json')"

echo
echo "== 3. Same types carried into the Parquet file =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 4. Nested geo object became nested Parquet columns (geo.city, geo.country) =="
clickhouse local -q "
SELECT c.1 AS column, c.2 AS parquet_path, c.3 AS physical_type
FROM file('events.parquet', ParquetMetadata) ARRAY JOIN columns AS c"

echo
echo "== 5. Read the typed columns back, including the nested fields =="
clickhouse local -q "
SELECT event_id, geo.country AS country, geo.city AS city, tags, amount
FROM file('events.parquet') ORDER BY event_id LIMIT 5"

echo
echo "== 6. Aggregate straight on the nested column =="
clickhouse local -q "
SELECT geo.country AS country, count() AS events, round(sum(amount), 2) AS total
FROM file('events.parquet') GROUP BY country ORDER BY total DESC"

echo
echo "== 7. Choose the compression codec (default is zstd) =="
clickhouse local -q "SELECT * FROM file('events_large.json') INTO OUTFILE 'events_zstd.parquet'         TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd'"
clickhouse local -q "SELECT * FROM file('events_large.json') INTO OUTFILE 'events_snappy.parquet'       TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='snappy'"
clickhouse local -q "SELECT * FROM file('events_large.json') INTO OUTFILE 'events_uncompressed.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='none'"
echo "zstd / snappy / none, bytes:"
stat -f '%z %N' events_zstd.parquet events_snappy.parquet events_uncompressed.parquet 2>/dev/null || stat -c '%s %n' events_zstd.parquet events_snappy.parquet events_uncompressed.parquet

echo
echo "== 8. JSON vs Parquet on disk (1,000,000 rows) =="
stat -f '%z %N' events_large.json events_zstd.parquet 2>/dev/null || stat -c '%s %n' events_large.json events_zstd.parquet

echo
echo "== 9. Perf: convert the 1,000,000-row events_large.json to Parquet (best-of-3, warm) =="
CMD="clickhouse local -q \"SELECT * FROM file('events_large.json') INTO OUTFILE 'events_large.parquet' TRUNCATE FORMAT Parquet\""
eval "$CMD" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p bash -c "$CMD" > /dev/null 2> /tmp/_jp_time.txt
  echo "run $i: $(grep real /tmp/_jp_time.txt)"
done
echo "rows in Parquet: $(clickhouse local -q "SELECT count() FROM file('events_large.parquet')")"
