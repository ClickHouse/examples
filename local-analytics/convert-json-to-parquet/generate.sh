#!/usr/bin/env bash
# Generate sample JSON locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.json        - SMALL_ROWS rows of JSONEachRow (NDJSON) with a
#                             nested "geo" object and a tags array (the worked example)
#   data/events_large.json  - LARGE_ROWS rows, the file used for the perf number
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-12}
LARGE_ROWS=${LARGE_ROWS:-1000000}

# JSONEachRow = one JSON object per line (NDJSON). The geo column is a real
# nested object; tags is an array. Both round-trip into typed Parquet columns.
gen() {
  local rows="$1" out="$2"
  clickhouse local -q "
  SELECT
    number + 1                                                                  AS event_id,
    toDateTime('2026-01-01 00:00:00') + (number * 37 % 2592000)                 AS ts,
    ['login','purchase','view','logout'][(number % 4) + 1]                      AS event_type,
    map(
      'country', ['GB','US','DE','FR','IN','AU'][(number % 6) + 1],
      'city',    ['London','NYC','Berlin','Paris','Mumbai','Sydney'][(number % 6) + 1]
    )                                                                           AS geo,
    arrayMap(x -> ['mobile','web','beta','vip'][(x % 4) + 1], range(number % 3)) AS tags,
    round(((number % 500) + 1) + (number % 100) / 100.0, 2)                      AS amount
  FROM numbers($rows)
  INTO OUTFILE '$out' TRUNCATE FORMAT JSONEachRow
  "
}

echo "Generating data/events.json ($SMALL_ROWS rows)..."
gen "$SMALL_ROWS" "data/events.json"

echo "Generating data/events_large.json ($LARGE_ROWS rows)..."
gen "$LARGE_ROWS" "data/events_large.json"

echo
echo "Generated files:"
ls -la data
