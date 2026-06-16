#!/usr/bin/env bash
# Generate sample Parquet files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.parquet        - 20 rows, mixed types incl. a nested tuple (the worked example)
#   data/events_large.parquet  - 3,000,000 rows, the perf number
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.parquet ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDateTime('2026-01-01 00:00:00') + (number * 3600)                 AS ts,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]              AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS amount,
  (number % 5 + 1)::UInt8                                              AS items,
  tuple(['mobile','desktop','tablet'][(number % 3) + 1], number % 2 = 0) AS device
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet
"

echo "Generating data/events_large.parquet ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                      AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                        AS ts,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['click','view','purchase','signup','refund'][(rand(3) % 5) + 1]               AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                            AS amount,
  (rand(5) % 5 + 1)::UInt8                                                        AS items
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.parquet' TRUNCATE FORMAT Parquet
"

echo
echo "Generated files:"
ls -la data
