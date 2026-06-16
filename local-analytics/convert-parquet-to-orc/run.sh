#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to ORC".
# Run ./generate.sh first to create the sample Parquet files in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> ORC in one line =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.orc' TRUNCATE FORMAT ORC"
echo "wrote events.orc"

echo
echo "== 2. Source Parquet schema (inferred, no DDL) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Resulting ORC schema (types carried over; ORC reads back Nullable) =="
clickhouse local -q "DESCRIBE file('events.orc')"

echo
echo "== 4. Same answer from both files (correctness check) =="
clickhouse local -q "SELECT 'parquet' AS src, country, count() AS c, round(sum(amount),2) AS amount FROM file('events.parquet') GROUP BY country ORDER BY country"
clickhouse local -q "SELECT 'orc'     AS src, country, count() AS c, round(sum(amount),2) AS amount FROM file('events.orc')     GROUP BY country ORDER BY country"

echo
echo "== 5. Choose the ORC compression codec =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events_zstd.orc' TRUNCATE FORMAT ORC SETTINGS output_format_orc_compression_method='zstd'"
ls -la events.orc events_zstd.orc

echo
echo "== 6. Perf: convert the 3,000,000-row events_large.parquet -> ORC (best-of-3, warm) =="
CMD="SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.orc' TRUNCATE FORMAT ORC"
clickhouse local -q "$CMD"   # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$CMD" > /dev/null 2> /tmp/_orc_time.txt
  echo "run $i: $(grep real /tmp/_orc_time.txt)"
done
echo "rows in ORC output:"
clickhouse local -q "SELECT count() FROM file('events_large.orc')"
ls -la events_large.parquet events_large.orc
