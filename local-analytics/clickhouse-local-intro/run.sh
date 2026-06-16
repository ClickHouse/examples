#!/usr/bin/env bash
# The exact commands from the article. Run ./generate.sh first.
set -euo pipefail
cd "$(dirname "$0")"

echo "=== 1. version (single self-contained binary) ==="
clickhouse local -q "SELECT version()"

echo
echo "=== 2. SELECT straight from a Parquet file, no import ==="
clickhouse local -q "
SELECT event, count() AS n, sum(amount) AS total
FROM file('events.parquet')
GROUP BY event ORDER BY n DESC"

echo
echo "=== 3. Schema is auto-inferred; DESCRIBE shows it ==="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "=== 4. Glob over many files + transparent .gz decompression ==="
clickhouse local -q "
SELECT splitByChar(' ', line)[5] AS status, count() AS n
FROM file('logs/app-*.log', LineAsString)
GROUP BY status ORDER BY n DESC"
echo "rows across the .gz file alone:"
clickhouse local -q "SELECT count() FROM file('logs/app-2026-06-02.log.gz', LineAsString)"

echo
echo "=== 5. Convert CSV -> Parquet in one line ==="
clickhouse local -q "SELECT * FROM file('sales.csv') INTO OUTFILE 'sales.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "SELECT count(), sum(spend) FROM file('sales.parquet')"

echo
echo "=== 6. JOIN across two different files in one query ==="
clickhouse local -q "
SELECT s.user AS user, count() AS sales, sum(s.spend) AS spend
FROM file('sales.csv') AS s
JOIN file('events.parquet') AS e ON toUInt64(s.id) = e.id
GROUP BY user ORDER BY spend DESC LIMIT 5"

echo
echo "=== 7. Query a remote file over HTTP with url() (skips if offline) ==="
if clickhouse local -q "SELECT 1 FROM url('https://datasets.clickhouse.com/hits_compatible/athena_partitioned/hits_1.parquet') LIMIT 1" >/dev/null 2>&1; then
  clickhouse local -q "
  SELECT count() AS rows
  FROM url('https://datasets.clickhouse.com/hits_compatible/athena_partitioned/hits_1.parquet')"
else
  echo "offline - skipping url() example"
fi
