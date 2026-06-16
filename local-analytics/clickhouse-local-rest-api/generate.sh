#!/usr/bin/env bash
# Generate a sample JSON REST-API response locally with clickhouse local, so the
# example has ZERO external dependencies. Writes into ./data/ (gitignored):
#   data/feed.json        - SMALL_ROWS JSONEachRow events (the worked example)
#   data/feed_large.json  - LARGE_ROWS JSONEachRow events (the perf number)
# run.sh serves ./data over http://127.0.0.1:PORT with `python3 -m http.server`,
# so url() can fetch them exactly like a live API. Idempotent: TRUNCATE overwrites.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-200}
LARGE_ROWS=${LARGE_ROWS:-1500000}

echo "Generating data/feed.json ($SMALL_ROWS rows, JSONEachRow)..."
clickhouse local -q "
SELECT
  number + 1                                                              AS id,
  toDateTime('2026-06-01 00:00:00') + (number * 137)                      AS ts,
  ['GB','US','DE','FR','IN','BR','JP','NL'][(number % 8) + 1]             AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]                  AS event,
  round(((number % 300) + 5) + (number % 100) / 100.0, 2)                AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/feed.json' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/feed_large.json ($LARGE_ROWS rows, JSONEachRow)..."
clickhouse local -q "
SELECT
  number + 1                                                              AS id,
  toDateTime('2026-06-01 00:00:00') + (rand(1) % 2592000)                 AS ts,
  ['GB','US','DE','FR','IN','BR','JP','NL','CA','AU'][(rand(2) % 10) + 1] AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                 AS event,
  round((rand(4) % 50000) / 100.0, 2)                                    AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/feed_large.json' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
