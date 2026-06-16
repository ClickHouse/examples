#!/usr/bin/env bash
# Generate the sample JSON (JSONL) files locally with clickhouse local, so
# nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - 8 rows, nested "user" object (the worked example)
#   data/events_large.jsonl  - 1,000,000 rows, ~137 MB (the perf number)
# Each line is one JSON object; the "user" field is a nested object, which is
# the whole point of this example: a nested object cannot map to a flat TSV
# column without being flattened first.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-1000000}

echo "Generating data/events.jsonl ($SMALL_ROWS rows, nested user object)..."
clickhouse local -q "
SELECT
  number + 1                                                              AS event_id,
  ['login','purchase','logout','signup'][(number % 4) + 1]               AS event_type,
  toDateTime('2026-06-01 00:00:00') + (number * 137)                     AS ts,
  map('id', toString(number % 50 + 1),
      'plan', ['free','pro','team'][(number % 3) + 1])                    AS user,
  ['web','ios','android'][(number % 3) + 1]                              AS source,
  round((number % 200) + 0.5, 2)                                         AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows, ~137 MB)..."
clickhouse local -q "
SELECT
  number + 1                                                                      AS event_id,
  ['login','purchase','logout','signup'][(rand(1) % 4) + 1]                       AS event_type,
  toDateTime('2026-06-01 00:00:00') + intDiv(number, 10)                          AS ts,
  map('id', toString(rand(2) % 100000),
      'plan', ['free','pro','team'][(rand(3) % 3) + 1])                           AS user,
  ['web','ios','android'][(rand(4) % 3) + 1]                                      AS source,
  round((rand(5) % 200000) / 100.0, 2)                                           AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
