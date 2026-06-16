#!/usr/bin/env bash
# Generate sample ClickHouse Native files locally with clickhouse local, so
# nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/events.native        - 20 rows (the worked example)
#   data/events.native.gz      - gzipped copy, to show transparent .native.gz reads
#   data/events_large.native   - 3,000,000 rows (the perf number)
#   data/events.csv            - the same 20 rows as CSV, for the size comparison
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# A typed SELECT; FORMAT Native writes the columns AND their exact types into
# the file, so no schema is ever needed on read.
SMALL_SELECT="
SELECT
  toDateTime('2026-01-01 00:00:00') + (number * 3607)                            AS event_time,
  (number + 1)::UInt32                                                           AS user_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                              AS country,
  ['click','purchase','refund','signup'][(number % 4) + 1]                       AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)::Decimal(10, 2)        AS revenue,
  (number % 5 + 1)::UInt8                                                         AS quantity
FROM numbers($SMALL_ROWS)
"

echo "Generating data/events.native ($SMALL_ROWS rows)..."
clickhouse local -q "$SMALL_SELECT INTO OUTFILE 'data/events.native' TRUNCATE FORMAT Native"

echo "Generating data/events.csv (same rows, for the size comparison)..."
clickhouse local -q "$SMALL_SELECT INTO OUTFILE 'data/events.csv' TRUNCATE FORMAT CSVWithNames"

echo "Generating data/events.native.gz..."
clickhouse local -q "SELECT * FROM file('data/events.native') INTO OUTFILE 'data/events.native.gz' TRUNCATE FORMAT Native"

echo "Generating data/events_large.native ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                       AS event_time,
  (number + 1)::UInt32                                                           AS user_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','purchase','refund','signup'][(rand(3) % 4) + 1]                      AS event_type,
  round((rand(4) % 50000) / 100.0, 2)::Decimal(10, 2)                            AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.native' TRUNCATE FORMAT Native
"

echo
echo "Generated files:"
ls -la data
