#!/usr/bin/env bash
# Generate the sample CSVs locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/orders.csv        - small, header + mixed types (the worked example)
#   data/notes.csv         - a CSV with a field that contains a comma and a tab,
#                            to show how the values survive the move to TSV
#   data/orders_large.csv  - the perf file (~3M rows, ~120 MB)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-12}
LARGE_ROWS=${LARGE_ROWS:-3000000}

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

echo "Generating data/notes.csv (fields containing a comma and a tab)..."
clickhouse local -q "
SELECT id, label, note FROM
(
  SELECT 1 AS id, 'red, large' AS label, 'line1\tline2' AS note
  UNION ALL
  SELECT 2 AS id, 'blue' AS label, 'plain' AS note
)
ORDER BY id
INTO OUTFILE 'data/notes.csv' TRUNCATE FORMAT CSVWithNames
"

echo "Generating data/orders_large.csv ($LARGE_ROWS rows)..."
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

echo
echo "Generated files:"
ls -la data
