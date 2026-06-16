#!/usr/bin/env bash
# Generate tiny sample data locally with clickhouse-local itself, so nothing
# large is committed to git. Idempotent: safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

rm -f events.parquet sales.csv sales.parquet
rm -rf logs
mkdir -p logs

# A small events table (parquet)
clickhouse local -q "
SELECT number AS id,
       ['login','click','purchase','logout'][(number % 4) + 1] AS event,
       toDate('2026-06-01') + (number % 5) AS day,
       (number * 7 % 100) AS amount
FROM numbers(1000)
INTO OUTFILE 'events.parquet' FORMAT Parquet"

# A small sales table (CSV with a header row)
clickhouse local -q "
SELECT number AS id,
       concat('user_', toString(number % 50)) AS user,
       (number * 3 % 500) AS spend
FROM numbers(200)
INTO OUTFILE 'sales.csv' FORMAT CSVWithNames"

# Two log files; gzip the second to show transparent decompression + globbing
for d in 01 02; do
  clickhouse local -q "
  SELECT concat(
           toString(toDateTime('2026-06-${d} 00:00:00') + number * 37),
           ' GET /api/', ['users','orders','events'][(number % 3) + 1],
           ' ', toString([200,200,404,500][(number % 4) + 1]))
  FROM numbers(300) FORMAT LineAsString" > "logs/app-2026-06-${d}.log"
done
gzip -kf logs/app-2026-06-02.log

echo "Generated:"
ls -1 events.parquet sales.csv logs/
