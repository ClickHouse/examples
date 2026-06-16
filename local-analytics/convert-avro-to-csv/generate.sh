#!/usr/bin/env bash
# Generate the sample Avro files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.avro        - 20 rows, includes a nested Tuple + an Array (the worked example)
#   data/events_large.avro  - 3,000,000 rows, ~81 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.avro ($SMALL_ROWS rows, with a nested Tuple + Array)..."
clickhouse local -q "
SELECT
  number + 1                                                       AS event_id,
  toDateTime('2026-01-01 00:00:00') + number * 3600                AS ts,
  ['login','purchase','logout','signup'][(number % 4) + 1]        AS event_type,
  ['GB','US','DE','FR'][(number % 4) + 1]                          AS country,
  round((number % 500) + (number % 100) / 100.0, 2)               AS amount,
  tuple('user' || toString(number % 5), (number % 5 + 1)::UInt8)  AS user_info,
  arraySlice(['a','b','c'], 1, (number % 3) + 1)                  AS tags
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.avro' TRUNCATE FORMAT Avro
"

echo "Generating data/events_large.avro ($LARGE_ROWS rows, ~81 MB)..."
clickhouse local -q "
SELECT
  number + 1                                                                 AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                   AS ts,
  ['login','purchase','logout','signup','view'][(rand(2) % 5) + 1]          AS event_type,
  ['GB','US','DE','FR','IN','AU','BR','JP'][(rand(3) % 8) + 1]              AS country,
  round((rand(4) % 50000) / 100.0, 2)                                       AS amount,
  tuple('user' || toString(rand(5) % 100000), (rand(6) % 10 + 1)::UInt8)    AS user_info,
  arraySlice(['a','b','c','d'], 1, (rand(7) % 4) + 1)                       AS tags
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.avro' TRUNCATE FORMAT Avro
"

echo
echo "Generated files:"
ls -la data
