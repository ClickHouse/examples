#!/usr/bin/env bash
# Generate the sample ORC files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.orc        - 20 rows, mixed types incl. a nested map (the worked example)
#   data/events_large.orc  - 3,000,000 rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.orc ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                                 AS event_date,
  number + 1                                                           AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','signup','purchase'][(number % 4) + 1]              AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)            AS amount,
  map('device', ['mobile','desktop'][(number % 2) + 1],
      'plan',   ['free','pro'][(number % 2) + 1])                     AS attrs
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.orc' TRUNCATE FORMAT ORC
"

echo "Generating data/events_large.orc ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                         AS event_date,
  number + 1                                                                     AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','view','signup','purchase','refund'][(rand(3) % 5) + 1]              AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                           AS amount,
  map('device', ['mobile','desktop'][(rand(5) % 2) + 1],
      'plan',   ['free','pro'][(rand(6) % 2) + 1])                              AS attrs
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.orc' TRUNCATE FORMAT ORC
"

echo
echo "Generated files:"
ls -la data
