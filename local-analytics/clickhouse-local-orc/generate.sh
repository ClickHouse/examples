#!/usr/bin/env bash
# Generate the sample ORC files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.orc        - 20 rows, mixed types (the worked example)
#   data/events_large.orc  - 3,000,000 rows (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.orc ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (number * 137)                   AS event_time,
  number + 1                                                           AS user_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['desktop','mobile','tablet'][(number % 3) + 1]                      AS device,
  ['click','view','purchase','refund'][(number % 4) + 1]              AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS revenue,
  (number % 5 + 1)::UInt8                                              AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.orc' TRUNCATE FORMAT ORC
"

echo "Generating data/events_large.orc ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                       AS event_time,
  number + 1                                                                     AS user_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['desktop','mobile','tablet'][(rand(3) % 3) + 1]                              AS device,
  ['click','view','purchase','refund'][(rand(6) % 4) + 1]                       AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                           AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                       AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.orc' TRUNCATE FORMAT ORC
"

echo
echo "Generated files:"
ls -la data
