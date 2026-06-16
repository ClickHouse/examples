#!/usr/bin/env bash
# Generate the sample JSONL (NDJSON) inputs locally with clickhouse local, so
# nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - SMALL_ROWS rows, one JSON object per line (the worked example)
#   data/events_large.jsonl  - LARGE_ROWS rows (the conversion-throughput number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                AS event_id,
  ['login','click','purchase','logout'][(number % 4) + 1]  AS event,
  ['GB','US','DE','FR'][(number % 4) + 1]                   AS country,
  round(((number % 50) + 1) + (number % 100) / 100.0, 2)   AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                          AS event_id,
  ['login','click','purchase','logout'][(rand(1) % 4) + 1]           AS event,
  ['GB','US','DE','FR','IN','AU','BR','JP'][(rand(2) % 8) + 1]       AS country,
  round((rand(3) % 50000) / 100.0, 2)                                AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
