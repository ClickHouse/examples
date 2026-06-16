#!/usr/bin/env bash
# Generate the sample CSVs locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.csv        - 20 rows, header + mixed types (the worked example)
#   data/events_large.csv  - 3,000,000 rows, ~120 MB (the throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.csv ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                                 AS event_date,
  number + 1                                                           AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]              AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)            AS amount,
  (number % 5 + 1)::UInt8                                             AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.csv' TRUNCATE FORMAT CSVWithNames
"

echo "Generating data/events_large.csv ($LARGE_ROWS rows, ~120 MB)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                          AS event_date,
  number + 1                                                                      AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['click','view','purchase','signup','share'][(rand(3) % 5) + 1]                AS action,
  round((rand(4) % 50000) / 100.0, 2)                                            AS amount,
  (rand(5) % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.csv' TRUNCATE FORMAT CSVWithNames
"

echo
echo "Generated files:"
ls -la data
