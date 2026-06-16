#!/usr/bin/env bash
# Generate the sample CSVs locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/orders.csv        - 20 rows, header + mixed types (the worked example)
#   data/orders.csv.gz     - gzipped copy, to show transparent .csv.gz reads
#   data/orders_large.csv  - 8,000,000 rows, ~338 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-8000000}

echo "Generating data/orders.csv ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                                 AS order_date,
  number + 1                                                           AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]            AS product,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS revenue,
  (number % 5 + 1)::UInt8                                              AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders.csv' TRUNCATE FORMAT CSVWithNames
"

echo "Generating data/orders_large.csv ($LARGE_ROWS rows, ~338 MB)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                          AS order_date,
  number + 1                                                                      AS order_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['widget','gadget','gizmo','doohickey','sprocket'][(rand(3) % 5) + 1]          AS product,
  round((rand(4) % 50000) / 100.0, 2)                                            AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/orders_large.csv' TRUNCATE FORMAT CSVWithNames
"

echo "Generating data/orders.csv.gz..."
clickhouse local -q "SELECT * FROM file('data/orders.csv') INTO OUTFILE 'data/orders.csv.gz' TRUNCATE FORMAT CSVWithNames"

echo
echo "Generated files:"
ls -la data
