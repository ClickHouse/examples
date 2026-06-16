#!/usr/bin/env bash
# Generate the sample NDJSON files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.ndjson        - 20 rows, one JSON object per line (the worked example)
#   data/events.ndjson.gz     - gzipped copy, to show transparent .ndjson.gz reads
#   data/events_large.ndjson  - 3,000,000 rows, ~600 MB-ish raw text (the perf number)
# NDJSON == JSON Lines == JSONL: one JSON object per line, no enclosing array.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.ndjson ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                           AS event_id,
  toDateTime('2026-06-01 00:00:00') + (number * 137)                   AS event_time,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]              AS event_type,
  round(((number % 200) + 5) + (number % 100) / 100.0, 2)            AS amount,
  (number % 5 + 1)::UInt8                                              AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.ndjson ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                     AS event_id,
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 15000000)                       AS event_time,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                       AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                           AS amount,
  (rand(5) % 5 + 1)::UInt8                                                       AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events.ndjson.gz..."
clickhouse local -q "SELECT * FROM file('data/events.ndjson', JSONEachRow) INTO OUTFILE 'data/events.ndjson.gz' TRUNCATE FORMAT JSONEachRow"

echo
echo "Generated files:"
ls -la data
