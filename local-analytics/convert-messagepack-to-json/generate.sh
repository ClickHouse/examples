#!/usr/bin/env bash
# Generate sample MsgPack files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.msgpack        - 20 rows, mixed types (the worked example)
#   data/events_large.msgpack  - 3,000,000 rows, ~93 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.msgpack ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                       AS event_id,
  toDateTime('2026-01-01 00:00:00') + (number * 137)               AS ts,
  ['login','click','purchase','logout'][(number % 4) + 1]          AS event_type,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                      AS country,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)          AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.msgpack' TRUNCATE FORMAT MsgPack
"

echo "Generating data/events_large.msgpack ($LARGE_ROWS rows, ~93 MB)..."
clickhouse local -q "
SELECT
  number + 1                                                                  AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                    AS ts,
  ['login','click','purchase','logout','signup'][(rand(2) % 5) + 1]           AS event_type,
  ['GB','US','DE','FR','IN','BR','JP','CA','NL','AU'][(rand(3) % 10) + 1]     AS country,
  round((rand(4) % 50000) / 100.0, 2)                                         AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.msgpack' TRUNCATE FORMAT MsgPack
"

echo
echo "Generated files:"
ls -la data
