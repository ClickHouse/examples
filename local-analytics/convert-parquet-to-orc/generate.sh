#!/usr/bin/env bash
# Generate sample Parquet files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.parquet        - small file (20 rows) with mixed types + a nested column
#   data/events_large.parquet  - ~3,000,000 rows, the perf number source
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.parquet ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                                 AS event_date,
  number + 1                                                           AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]              AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS amount,
  map('utm','spring','tier', toString(number % 3))                    AS tags
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet
"

echo "Generating data/events_large.parquet ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                         AS event_date,
  number + 1                                                                     AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','view','purchase','signup','share'][(rand(3) % 5) + 1]               AS action,
  round((rand(4) % 50000) / 100.0, 2)                                           AS amount,
  map('utm','spring','tier', toString(rand(6) % 3))                             AS tags
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.parquet' TRUNCATE FORMAT Parquet
"

echo
echo "Generated files:"
ls -la data
