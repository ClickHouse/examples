#!/usr/bin/env bash
# Generate the sample JSON Lines (JSONL / NDJSON) files locally with clickhouse
# local, so nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl       - 20 rows, one JSON object per line (the worked example)
#   data/events.jsonl.gz    - gzipped copy, to show transparent .jsonl.gz reads
#   data/events_large.jsonl - 3,000,000 rows, ~360 MB (the perf number)
# JSON Lines is the same thing as NDJSON / JSONL: one JSON object per line.
# ClickHouse reads/writes it with the JSONEachRow format.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (number * 3600)                  AS event_time,
  number + 1                                                           AS user_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]              AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)             AS revenue,
  (number % 5 + 1)::UInt8                                              AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows, ~360 MB)..."
clickhouse local -q "
SELECT
  toDateTime('2026-01-01 00:00:00') + (rand(1) % 31536000)                       AS event_time,
  number + 1                                                                     AS user_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]         AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                        AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                            AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                        AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events.jsonl.gz..."
clickhouse local -q "SELECT * FROM file('data/events.jsonl') INTO OUTFILE 'data/events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"

echo
echo "Generated files:"
ls -la data
