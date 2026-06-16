#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to Arrow".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> Arrow in one line =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.arrow' TRUNCATE FORMAT Arrow"
clickhouse local -q "SELECT * FROM file('events.arrow') LIMIT 5"

echo
echo "== 2. Types carried from CSV inference into the Arrow file =="
echo "-- CSV (text, types inferred):"
clickhouse local -q "DESCRIBE file('events.csv')"
echo "-- Arrow (types embedded in the file's schema):"
clickhouse local -q "DESCRIBE file('events.arrow')"

echo
echo "== 3. Feather is the Arrow IPC format (same FORMAT, .feather extension) =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.feather' TRUNCATE FORMAT Arrow"
clickhouse local -q "SELECT count() FROM file('events.feather')"

echo
echo "== 4. Compress the Arrow buffers (zstd) =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.zstd.arrow' TRUNCATE FORMAT Arrow SETTINGS output_format_arrow_compression_method='zstd'"
clickhouse local -q "SELECT count() FROM file('events.zstd.arrow')"

echo
echo "== 5. Query the Arrow file directly (columnar + typed, no re-parse) =="
clickhouse local -q "SELECT country, count() AS events, round(sum(amount),2) AS amount FROM file('events.arrow') GROUP BY country ORDER BY amount DESC LIMIT 5"

echo
echo "== 6. Perf: convert the 3M-row, ~129 MB events_large.csv -> Arrow (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.arrow' TRUNCATE FORMAT Arrow"  # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.arrow' TRUNCATE FORMAT Arrow" 2> /tmp/_arrow_time.txt
  echo "run $i: $(grep real /tmp/_arrow_time.txt)"
done
echo "-- on-disk sizes:"
ls -lh events_large.csv events_large.arrow | awk '{print $5, $9}'
echo "-- roundtrip row count:"
clickhouse local -q "SELECT count() FROM file('events_large.arrow')"
