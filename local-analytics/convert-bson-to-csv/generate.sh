#!/usr/bin/env bash
# Generate the sample BSON files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.bson        - SMALL_ROWS rows (default 20); each row has a nested
#                             `geo` sub-document (city, country) -> the flatten gotcha
#   data/events_large.bson  - LARGE_ROWS rows (default 1,400,000, ~146 MB) for perf
# BSONEachRow writes one BSON document per row, the same shape mongoexport emits.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1400000}

echo "Generating data/events.bson ($SMALL_ROWS rows, with a nested geo sub-document)..."
clickhouse local -q "
SELECT
  number + 1                                                                AS event_id,
  ['signup','purchase','login','refund'][(number % 4) + 1]                  AS event_type,
  map(
    'city',    ['London','Berlin','Paris','Austin'][(number % 4) + 1],
    'country', ['GB','DE','FR','US'][(number % 4) + 1]
  )                                                                         AS geo,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)                   AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.bson' TRUNCATE FORMAT BSONEachRow
"

echo "Generating data/events_large.bson ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                AS event_id,
  ['signup','purchase','login','refund','view'][(rand(1) % 5) + 1]          AS event_type,
  map(
    'city',    ['London','Berlin','Paris','Austin','Tokyo'][(rand(2) % 5) + 1],
    'country', ['GB','DE','FR','US','JP'][(rand(2) % 5) + 1]
  )                                                                         AS geo,
  round((rand(3) % 50000) / 100.0, 2)                                       AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.bson' TRUNCATE FORMAT BSONEachRow
"

echo
echo "Generated files:"
ls -la data
