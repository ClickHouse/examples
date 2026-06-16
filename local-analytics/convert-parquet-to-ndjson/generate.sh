#!/usr/bin/env bash
# Generate the sample Parquet files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.parquet        - 20 rows, typed + a nested column (the worked example)
#   data/events_large.parquet  - 3,000,000 rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.parquet ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDateTime('2026-06-01 00:00:00') + (number * 3600)                  AS ts,
  ['login','purchase','logout','view'][(number % 4) + 1]               AS action,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                         AS country,
  round(((number % 200) + 1) + (number % 100) / 100.0, 2)             AS amount,
  (number % 2 = 0)                                                     AS is_member,
  map('os', ['mac','win','linux'][(number % 3) + 1],
      'plan', ['free','pro'][(number % 2) + 1])                        AS attrs
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet
"

echo "Generating data/events_large.parquet ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                      AS event_id,
  toDateTime('2026-06-01 00:00:00') + (rand(1) % 2592000)                         AS ts,
  ['login','purchase','logout','view','search'][(rand(2) % 5) + 1]                AS action,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(3) % 10) + 1]         AS country,
  round((rand(4) % 50000) / 100.0, 2)                                            AS amount,
  (rand(5) % 2 = 0)                                                               AS is_member,
  map('os', ['mac','win','linux'][(rand(6) % 3) + 1],
      'plan', ['free','pro'][(rand(7) % 2) + 1])                                  AS attrs
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.parquet' TRUNCATE FORMAT Parquet
"

echo
echo "Generated files:"
ls -la data
