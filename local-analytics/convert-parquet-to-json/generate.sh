#!/usr/bin/env bash
# Generate the sample Parquet files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.parquet        - small, typed + nested columns (the worked example)
#   data/events_large.parquet  - ~3,000,000 rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# Small file: deliberately includes a typed Date, a Decimal, a DateTime, and a
# nested column (Array(String) tags + a Tuple as a nested object) so the
# Parquet -> JSON type/nesting behaviour is visible.
echo "Generating data/events.parquet ($SMALL_ROWS rows, typed + nested)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDate('2026-01-01') + (number % 7)                                  AS event_date,
  toDateTime('2026-01-01 00:00:00') + (number * 3600)                  AS event_ts,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                         AS country,
  toDecimal64(((number % 500) + 5) + (number % 100) / 100.0, 2)        AS amount,
  splitByChar(',', ['new,paid','web','api,mobile','beta'][(number % 4) + 1]) AS tags,
  CAST(
    (['acme','globex','initech','umbrella'][(number % 4) + 1], (number % 9 + 1)::UInt8),
    'Tuple(name String, tier UInt8)'
  ) AS account
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet
"

echo "Generating data/events_large.parquet ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                      AS event_id,
  toDate('2026-01-01') + (rand(1) % 365)                                          AS event_date,
  toDateTime('2026-01-01 00:00:00') + (rand(6) % 31536000)                        AS event_ts,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  toDecimal64((rand(4) % 50000) / 100.0, 2)                                       AS amount,
  splitByChar(',', ['new,paid','web','api,mobile','beta','new'][(rand(3) % 5) + 1]) AS tags,
  CAST(
    (['acme','globex','initech','umbrella'][(rand(7) % 4) + 1], (rand(8) % 9 + 1)::UInt8),
    'Tuple(name String, tier UInt8)'
  ) AS account
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.parquet' TRUNCATE FORMAT Parquet
"

echo
echo "Generated files:"
ls -la data
