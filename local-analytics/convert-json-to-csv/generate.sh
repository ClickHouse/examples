#!/usr/bin/env bash
# Generate sample JSON locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - 20 rows of newline-delimited JSON with a nested
#                              object (user) and an array (amounts) - the
#                              worked example for the flattening step
#   data/events_large.jsonl  - 1,000,000 rows, ~125 MB, same shape (perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1000000}

gen() { # $1 = row count, $2 = output path
  clickhouse local -q "
  SELECT
    number + 1                                                          AS event_id,
    ['login','purchase','logout','signup'][(number % 4) + 1]            AS event_type,
    toDateTime('2026-06-01 09:00:00') + number * 37                     AS ts,
    map(
      'country', ['GB','US','DE','FR','IN'][(number % 5) + 1],
      'plan',    ['free','pro','team'][(number % 3) + 1]
    )                                                                   AS user,
    [round(((number % 500) + 1.5), 2), round(((number % 80) + 0.5), 2)] AS amounts
  FROM numbers($1)
  INTO OUTFILE '$2' TRUNCATE FORMAT JSONEachRow
  "
}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
gen "$SMALL_ROWS" 'data/events.jsonl'

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows, ~125 MB)..."
gen "$LARGE_ROWS" 'data/events_large.jsonl'

echo
echo "Generated files:"
ls -la data
