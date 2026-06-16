#!/usr/bin/env bash
# Generate sample JSONL (JSONEachRow) locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - SMALL_ROWS rows, mixed types incl. a nested object
#   data/events_large.jsonl  - LARGE_ROWS rows (~the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1000000}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDateTime('2026-01-01 00:00:00') + (number * 137)                   AS ts,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                     AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]               AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)              AS amount,
  (number % 3 = 0)                                                      AS is_member,
  map('os', ['ios','android','web'][(number % 3) + 1],
      'ver', toString((number % 5) + 1))                               AS device
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                       AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                         AS ts,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]          AS country,
  ['click','view','purchase','signup'][(rand(3) % 4) + 1]                          AS action,
  round((rand(4) % 50000) / 100.0, 2)                                              AS amount,
  (rand(5) % 2 = 0)                                                                 AS is_member,
  map('os', ['ios','android','web'][(rand(6) % 3) + 1],
      'ver', toString((rand(7) % 5) + 1))                                          AS device
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
