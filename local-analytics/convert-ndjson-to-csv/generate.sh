#!/usr/bin/env bash
# Generate sample NDJSON locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.ndjson        - small file, nested objects + array (the worked example)
#   data/events_large.ndjson  - LARGE_ROWS rows (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1000000}

echo "Generating data/events.ndjson ($SMALL_ROWS rows, nested objects + array)..."
clickhouse local -q "
SELECT
  number + 1                                                            AS event_id,
  toDateTime('2026-06-01 00:00:00') + (number * 137)                    AS ts,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                          AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]               AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)              AS amount,
  map('os', ['macos','linux','windows'][(number % 3) + 1],
      'app_version', concat('2.', toString(number % 10)))              AS device,
  range(number % 3)                                                     AS tags
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.ndjson ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                       AS event_id,
  toDateTime('2026-06-01 00:00:00') + (rand(1) % 2592000)                          AS ts,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]          AS country,
  ['click','view','purchase','signup'][(rand(3) % 4) + 1]                         AS action,
  round((rand(4) % 50000) / 100.0, 2)                                             AS amount,
  map('os', ['macos','linux','windows'][(rand(5) % 3) + 1],
      'app_version', concat('2.', toString(rand(6) % 10)))                        AS device,
  range(rand(7) % 3)                                                               AS tags
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
echo
echo "First two NDJSON lines (note the nested device object and tags array):"
head -n 2 data/events.ndjson
