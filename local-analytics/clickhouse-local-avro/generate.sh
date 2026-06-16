#!/usr/bin/env bash
# Generate the sample Avro files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.avro       - 20 rows, mixed types incl. date + timestamp-millis (logical types)
#   data/events_large.avro - 3,000,000 rows (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.avro ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                                          AS event_date,
  toDateTime64('2026-01-01 00:00:00.000', 3) + number * 137                      AS event_time,
  (number + 1)::UInt32                                                          AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                             AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]                        AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)                       AS revenue,
  (number % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.avro' TRUNCATE FORMAT Avro
"

echo "Generating data/events_large.avro ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                        AS event_date,
  toDateTime64('2026-01-01 00:00:00.000', 3) + (rand(6) % 31536000)             AS event_time,
  (number + 1)::UInt32                                                          AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]       AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                       AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                           AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                       AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.avro' TRUNCATE FORMAT Avro
"

echo
echo "Generated files:"
ls -la data
