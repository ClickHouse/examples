#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.parquet' TRUNCATE FORMAT Parquet"
ls -la orders.csv orders.parquet | awk '{print $5"\t"$NF}'

echo
echo "== 2. Types carried from the CSV into the Parquet schema =="
clickhouse local -q "DESCRIBE file('orders.parquet')"

echo
echo "== 3. Pick the compression codec and row-group size =="
clickhouse local -q "
SELECT * FROM file('orders.csv')
INTO OUTFILE 'orders_zstd.parquet' TRUNCATE FORMAT Parquet
SETTINGS output_format_parquet_compression_method='zstd', output_format_parquet_row_group_size=1000000
"
echo "Per-column codec recorded in the Parquet footer:"
clickhouse local -q "
SELECT c.1 AS column, c.2 AS physical_type, c.3 AS compression
FROM (
  SELECT arrayJoin(arrayMap(x -> (x.name, x.physical_type, x.compression), columns)) AS c
  FROM file('orders_zstd.parquet', ParquetMetadata)
)
FORMAT TSV
"

echo
echo "== 4. Override the inferred types before writing (tighter, non-nullable) =="
clickhouse local -q "
SELECT * FROM file('orders.csv', 'CSVWithNames',
  'order_date Date, order_id UInt32, country LowCardinality(String), product LowCardinality(String), revenue Float64, quantity UInt8')
INTO OUTFILE 'orders_typed.parquet' TRUNCATE FORMAT Parquet
SETTINGS output_format_parquet_compression_method='zstd'
"
clickhouse local -q "DESCRIBE file('orders_typed.parquet')"

echo
echo "== 5. Compression comparison on the large file (132 MB CSV) =="
clickhouse local -q "SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large_zstd.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd', output_format_parquet_row_group_size=1000000"
clickhouse local -q "SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large_lz4.parquet'  TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='lz4'"
ls -la orders_large.csv orders_large_zstd.parquet orders_large_lz4.parquet | awk '{print $5"\t"$NF}'

echo
echo "== 6. Conversion throughput: 3,000,000-row, ~132 MB CSV -> zstd Parquet (best-of-3, warm) =="
Q="SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large_zstd.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd', output_format_parquet_row_group_size=1000000"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_cv_time.txt
  echo "run $i: $(grep real /tmp/_cv_time.txt)"
done

echo
echo "== 7. Read the Parquet back: same SQL, columnar and typed =="
clickhouse local -q "
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('orders_large_zstd.parquet')
GROUP BY country ORDER BY revenue DESC LIMIT 5
"
