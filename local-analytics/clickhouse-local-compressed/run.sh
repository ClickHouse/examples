#!/usr/bin/env bash
# The exact commands from the article "How to query a compressed file".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read a gzipped CSV with no decompress step (.csv.gz) =="
clickhouse local -q "SELECT * FROM file('events.csv.gz') LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. The schema is inferred straight through the gzip =="
clickhouse local -q "DESCRIBE file('events.csv.gz') FORMAT PrettyCompact"

echo
echo "== 3. A zstd-compressed CSV reads the same way (.csv.zst) =="
clickhouse local -q "SELECT event_type, count() FROM file('events.csv.zst') GROUP BY event_type ORDER BY event_type FORMAT PrettyCompact"

echo
echo "== 4. Parquet with zstd column compression: nothing special to do =="
clickhouse local -q "SELECT count(), round(sum(revenue), 2) FROM file('events.zstd.parquet') FORMAT PrettyCompact"

echo
echo "== 5. Force the codec when the extension does not reveal it =="
cp events.csv.gz events.bin   # a gzipped CSV with an opaque name
echo "-- auto-detection has nothing to go on, so this fails:"
clickhouse local -q "SELECT count() FROM file('events.bin', CSVWithNames)" 2>&1 | head -1 || true
echo "-- pass the compression method as the 4th argument to file():"
clickhouse local -q "
SELECT count() FROM file('events.bin', 'CSVWithNames',
  'event_time DateTime, user_id Int64, country String, device String, event_type String, revenue Float64, quantity UInt8',
  'gzip')"
rm -f events.bin

echo
echo "== 6. Aggregate directly on the compressed file =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue), 2) AS revenue
FROM file('events.csv.gz')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 7. Perf: aggregate the 3M-row gzipped CSV (~49 MiB on disk, ~173 MiB raw) =="
echo "   best-of-3, warm OS page cache; gzip is decoded on every run"
Q="SELECT country, count() AS events, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('events_large.csv.gz') WHERE event_type='purchase' GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" > /dev/null   # warm the cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_compressed_time.txt
  echo "run $i: $(grep real /tmp/_compressed_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
