#!/usr/bin/env bash
# Generate the sample Parquet files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.parquet        - SMALL_ROWS rows, mixed types + a nested column
#                                (the worked example)
#   data/events_large.parquet  - LARGE_ROWS rows (the perf number)
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
  toDateTime('2026-01-01 00:00:00') + (number * 137)                   AS ts,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]              AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS amount,
  map('os', ['ios','android','web'][(number % 3) + 1],
      'version', toString((number % 4) + 1))                          AS attrs
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet
"

echo "Generating data/events_large.parquet ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                      AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                        AS ts,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['click','view','purchase','signup','share'][(rand(3) % 5) + 1]                AS action,
  round((rand(4) % 50000) / 100.0, 2)                                            AS amount,
  map('os', ['ios','android','web'][(rand(5) % 3) + 1],
      'version', toString((rand(6) % 4) + 1))                                     AS attrs
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.parquet' TRUNCATE FORMAT Parquet
"

echo
echo "Generated files:"
ls -la data
