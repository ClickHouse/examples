#!/usr/bin/env bash
# Generate sample ORC files locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.orc        - SMALL_ROWS rows, mixed types incl. a nested column
#                            (the worked example for the conversion)
#   data/events_large.orc  - LARGE_ROWS rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.orc ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (number * 137)                       AS event_time,
  number + 1                                                               AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                        AS country,
  ['click','view','purchase','signup'][(number % 4) + 1]                   AS action,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)                  AS amount,
  map('utm_source', ['ads','organic','email'][(number % 3) + 1],
      'device', ['mobile','desktop'][(number % 2) + 1])                    AS tags
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.orc' TRUNCATE FORMAT ORC
"

echo "Generating data/events_large.orc ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                          AS event_time,
  number + 1                                                                        AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]            AS country,
  ['click','view','purchase','signup','share'][(rand(3) % 5) + 1]                   AS action,
  round((rand(4) % 50000) / 100.0, 2)                                               AS amount,
  map('utm_source', ['ads','organic','email'][(rand(6) % 3) + 1],
      'device', ['mobile','desktop'][(rand(7) % 2) + 1])                            AS tags
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.orc' TRUNCATE FORMAT ORC
"

echo
echo "Generated files:"
ls -la data
