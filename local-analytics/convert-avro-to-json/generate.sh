#!/usr/bin/env bash
# Generate sample Avro files locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.avro        - 20 rows, embedded schema (the worked example)
#   data/events_large.avro  - 3,000,000 rows (the perf number)
# Avro embeds its own schema, so the reader needs no structure argument.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

gen() {
  local rows="$1" out="$2"
  clickhouse local -q "
  SELECT
    number + 1                                                          AS event_id,
    ['login','purchase','logout','signup'][(number % 4) + 1]            AS event_type,
    ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
    round((number % 5000) / 100.0, 2)                                   AS amount,
    toDateTime('2026-01-01 00:00:00') + (number % 86400)                AS ts
  FROM numbers($rows)
  INTO OUTFILE '$out' TRUNCATE FORMAT Avro
  "
}

echo "Generating data/events.avro ($SMALL_ROWS rows)..."
gen "$SMALL_ROWS" "data/events.avro"

echo "Generating data/events_large.avro ($LARGE_ROWS rows)..."
gen "$LARGE_ROWS" "data/events_large.avro"

echo
echo "Generated files:"
ls -la data
