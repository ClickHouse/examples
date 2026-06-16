#!/usr/bin/env bash
# Generate the sample ORC files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.orc        - SMALL_ROWS rows, typed columns incl. a nested struct
#   data/events_large.orc  - LARGE_ROWS rows (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.orc ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDate('2026-01-01') + (number % 31)                                 AS event_date,
  ['login','purchase','refund','view'][(number % 4) + 1]               AS action,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                         AS country,
  toDecimal64(((number % 500) + 5) + (number % 100) / 100.0, 2)        AS amount,
  CAST((number % 6 + 1, ['web','ios','android'][(number % 3) + 1]), 'Tuple(user_id UInt16, platform String)') AS source
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.orc' TRUNCATE FORMAT ORC
SETTINGS output_format_orc_string_as_string = 1
"

echo "Generating data/events_large.orc ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                   AS event_id,
  toDate('2026-01-01') + (rand(1) % 365)                                       AS event_date,
  ['login','purchase','refund','view'][(rand(2) % 4) + 1]                      AS action,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(3) % 10) + 1]      AS country,
  toDecimal64((rand(4) % 50000) / 100.0, 2)                                    AS amount,
  CAST((rand(5) % 6 + 1, ['web','ios','android'][(rand(6) % 3) + 1]), 'Tuple(user_id UInt16, platform String)') AS source
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.orc' TRUNCATE FORMAT ORC
SETTINGS output_format_orc_string_as_string = 1
"

echo
echo "Generated files:"
ls -la data
