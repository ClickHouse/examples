#!/usr/bin/env bash
# Generate sample RowBinary files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.rowbinary        - SMALL_ROWS rows, RowBinaryWithNamesAndTypes (self-describing)
#   data/events_plain.rowbinary  - same rows, plain RowBinary (no header, needs explicit structure)
#   data/events_large.rowbinary  - LARGE_ROWS rows, RowBinaryWithNamesAndTypes (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# The shared SELECT used for the small files. Deterministic (no rand) so the
# worked example output is stable.
SMALL_SELECT="
SELECT
  toDateTime('2026-01-01 00:00:00') + (number * 137)                    AS event_time,
  (number + 1)::UInt32                                                  AS user_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                     AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]               AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)::Float64     AS revenue,
  (number % 5 + 1)::UInt8                                               AS quantity
FROM numbers($SMALL_ROWS)
"

echo "Generating data/events.rowbinary ($SMALL_ROWS rows, RowBinaryWithNamesAndTypes)..."
clickhouse local -q "$SMALL_SELECT INTO OUTFILE 'data/events.rowbinary' TRUNCATE FORMAT RowBinaryWithNamesAndTypes"

echo "Generating data/events_plain.rowbinary ($SMALL_ROWS rows, plain RowBinary, no header)..."
clickhouse local -q "$SMALL_SELECT INTO OUTFILE 'data/events_plain.rowbinary' TRUNCATE FORMAT RowBinary"

echo "Generating data/events_large.rowbinary ($LARGE_ROWS rows, RowBinaryWithNamesAndTypes)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                        AS event_time,
  (number + 1)::UInt32                                                            AS user_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                        AS event_type,
  round((rand(4) % 50000) / 100.0, 2)::Float64                                   AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.rowbinary' TRUNCATE FORMAT RowBinaryWithNamesAndTypes
"

echo
echo "Generated files:"
ls -la data
