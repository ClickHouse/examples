#!/usr/bin/env bash
# Generate sample NDJSON locally with clickhouse local, so nothing large is
# committed to git. NDJSON and JSONL are the same format (one JSON object per
# line); ClickHouse reads both with the JSONEachRow format. Writes ./data/:
#   data/events.ndjson        - small, header-free, with a NESTED object + array (worked example)
#   data/events_large.ndjson  - LARGE_ROWS rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1000000}

echo "Generating data/events.ndjson ($SMALL_ROWS rows, with nested object + array)..."
clickhouse local -q "
SELECT
  number + 1                                                            AS event_id,
  toDateTime('2026-01-01 00:00:00') + (number * 137)                    AS ts,
  ['login','purchase','logout','view'][(number % 4) + 1]                AS event_type,
  map('country', ['GB','US','DE','FR'][(number % 4) + 1],
      'plan',    ['free','pro','team'][(number % 3) + 1])               AS user,
  arrayMap(i -> (number + i) % 100, range((number % 3) + 1))            AS items,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)              AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.ndjson ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                       AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                         AS ts,
  ['login','purchase','logout','view','search'][(rand(2) % 5) + 1]                 AS event_type,
  map('country', ['GB','US','DE','FR','IN','AU','BR','JP'][(rand(3) % 8) + 1],
      'plan',    ['free','pro','team'][(rand(4) % 3) + 1])                          AS user,
  arrayMap(i -> (rand(5) + i) % 1000, range((rand(6) % 3) + 1))                     AS items,
  round((rand(7) % 50000) / 100.0, 2)                                              AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
echo
echo "First 2 lines of data/events.ndjson:"
head -n 2 data/events.ndjson
