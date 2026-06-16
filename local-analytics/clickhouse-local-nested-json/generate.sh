#!/usr/bin/env bash
# Generate the sample nested-JSON files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.jsonl        - SMALL_ROWS rows (default 5), the worked example.
#                              Each line is a JSON object with a nested user object
#                              (user.geo.country), an array of item objects, and an
#                              irregular `props` object whose keys vary by event_type.
#   data/events.jsonl.gz     - gzipped copy, to show transparent .jsonl.gz reads.
#   data/events_large.jsonl  - LARGE_ROWS rows (default 500,000, ~137 MB) for the perf number.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-500000}

gen() {
  local rows="$1" out="$2"
  clickhouse local -q "
  SELECT
    number + 1 AS event_id,
    formatDateTime(toDateTime('2026-06-01 00:00:00') + number*611, '%Y-%m-%dT%H:%i:%SZ') AS ts,
    ['login','purchase','view','refund'][(number % 4) + 1] AS event_type,
    CAST(tuple(
      toUInt32(1000 + number % 40),
      ['Ada','Lin','Sam','Mei','Omar'][(number % 5) + 1],
      tuple(
        ['GB','US','DE','FR','IN'][(number % 5) + 1],
        ['London','NYC','Berlin','Paris','Delhi'][(number % 5) + 1]
      )
    ), 'Tuple(id UInt32, name String, geo Tuple(country String, city String))') AS user,
    CAST(arrayMap(i -> tuple(
        ['SKU-A','SKU-B','SKU-C','SKU-D'][(i + number) % 4 + 1],
        toUInt8(i + 1),
        round(((i + number) % 90 + 10) + 0.99, 2)
      ), range((number % 3) + 1)), 'Array(Tuple(sku String, qty UInt8, price Float64))') AS items,
    multiIf(
      event_type = 'login',    '{\"method\":\"sso\",\"mfa\":true}',
      event_type = 'purchase', '{\"coupon\":\"SUMMER\",\"gateway\":\"stripe\",\"installments\":3}',
      event_type = 'refund',   '{\"reason\":\"damaged\",\"approved_by\":\"agent-7\"}',
                               '{\"referrer\":\"newsletter\"}'
    )::JSON AS props
  FROM numbers($rows)
  INTO OUTFILE '$out' TRUNCATE
  SETTINGS output_format_json_named_tuples_as_objects = 1, enable_json_type = 1
  FORMAT JSONEachRow
  "
}

echo "Generating data/events.jsonl ($SMALL_ROWS rows)..."
gen "$SMALL_ROWS" 'data/events.jsonl'

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows)..."
gen "$LARGE_ROWS" 'data/events_large.jsonl'

echo "Generating data/events.jsonl.gz..."
clickhouse local -q "SELECT * FROM file('data/events.jsonl', JSONEachRow) INTO OUTFILE 'data/events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"

echo
echo "Generated files:"
ls -la data
