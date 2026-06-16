#!/usr/bin/env bash
# Generate sample JSONL (NDJSON) locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - SMALL_ROWS rows, one JSON object per line, with a
#                              nested "geo" object and a "tags" array (the angle)
#   data/events_large.jsonl  - LARGE_ROWS rows (~the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-12}
LARGE_ROWS=${LARGE_ROWS:-1200000}

gen() {
  local rows="$1" out="$2"
  clickhouse local -q "
  SELECT
    number + 1                                                          AS event_id,
    toDateTime('2026-06-01 00:00:00') + number * 137                    AS ts,
    ['login','click','purchase','logout'][(number % 4) + 1]            AS action,
    map(
      'country', ['GB','US','DE','FR'][(number % 4) + 1],
      'city',    ['London','New York','Berlin','Paris'][(number % 4) + 1]
    )                                                                    AS geo,
    arrayMap(x -> ['mobile','web','beta','vip'][(x % 4) + 1], range(number % 3)) AS tags
  FROM numbers($rows)
  INTO OUTFILE '$out' TRUNCATE FORMAT JSONEachRow
  "
}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
gen "$SMALL_ROWS" "data/events.jsonl"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows)..."
gen "$LARGE_ROWS" "data/events_large.jsonl"

echo
echo "Generated files:"
ls -la data
echo
echo "First two lines of data/events.jsonl:"
head -n 2 data/events.jsonl
