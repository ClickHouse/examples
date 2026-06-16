#!/usr/bin/env bash
# Generate sample data locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/sales/2026-01.csv .. 2026-04.csv  - 4 monthly CSVs (the glob example)
#   data/events/part-00.parquet .. part-03.parquet - 4 Parquet parts (parquet glob)
#   data/sales_large/2026-01.csv .. (12 files, LARGE_ROWS total) - the perf set
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data/sales data/events data/sales_large

SMALL_ROWS=${SMALL_ROWS:-50}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating 4 monthly CSVs in data/sales/ ($SMALL_ROWS rows each)..."
for m in 01 02 03 04; do
  clickhouse local -q "
  SELECT
    toDate('2026-$m-01') + (number % 28)                                AS sale_date,
    number + 1                                                          AS order_id,
    ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                   AS country,
    ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]          AS product,
    round(((number % 480) + 5) + (number % 100) / 100.0, 2)           AS revenue,
    (number % 5 + 1)::UInt8                                            AS quantity
  FROM numbers($SMALL_ROWS)
  INTO OUTFILE 'data/sales/2026-$m.csv' TRUNCATE FORMAT CSVWithNames
  "
done

echo "Generating 4 Parquet parts in data/events/ ($SMALL_ROWS rows each)..."
for p in 00 01 02 03; do
  clickhouse local -q "
  SELECT
    toDateTime('2026-01-01 00:00:00') + (number * 137 + $p * 9999)     AS event_time,
    number + 1 + ($p * 1000)                                           AS user_id,
    ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                  AS country,
    ['click','view','purchase','refund'][(number % 4) + 1]           AS event_type,
    round(((number % 300) + 1) + (number % 100) / 100.0, 2)         AS revenue
  FROM numbers($SMALL_ROWS)
  INTO OUTFILE 'data/events/part-$p.parquet' TRUNCATE FORMAT Parquet
  "
done

echo "Generating 12 monthly CSVs in data/sales_large/ (~$LARGE_ROWS rows total)..."
PER_FILE=$(( LARGE_ROWS / 12 ))
for m in 01 02 03 04 05 06 07 08 09 10 11 12; do
  clickhouse local -q "
  SELECT
    toDate('2026-$m-01') + (rand(1) % 28)                                       AS sale_date,
    number + 1                                                                  AS order_id,
    ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]     AS country,
    ['widget','gadget','gizmo','doohickey','sprocket'][(rand(3) % 5) + 1]      AS product,
    round((rand(4) % 50000) / 100.0, 2)                                        AS revenue,
    (rand(5) % 5 + 1)::UInt8                                                    AS quantity
  FROM numbers($PER_FILE)
  INTO OUTFILE 'data/sales_large/2026-$m.csv' TRUNCATE FORMAT CSVWithNames
  "
done

echo
echo "Generated files:"
ls -la data/sales data/events
echo "data/sales_large/: $(ls data/sales_large | wc -l | tr -d ' ') files, $(du -sh data/sales_large | cut -f1) total"
