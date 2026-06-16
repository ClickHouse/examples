#!/usr/bin/env bash
# Generate the sample JSON files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.json        - top-level JSON array, 20 rows, with a nested object
#                             and an array column (the worked example)
#   data/events.jsonl       - same rows as JSONEachRow (one object per line)
#   data/events.jsonl.gz    - gzipped JSONEachRow, to show transparent .gz reads
#   data/events_large.jsonl - 3,000,000 rows JSONEachRow (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# The small worked example: a nested "geo" object and an array "tags" column,
# so we can show dot access and arrayJoin.
echo "Generating data/events.jsonl ($SMALL_ROWS rows, JSONEachRow)..."
clickhouse local -q "
SELECT
  number + 1                                                              AS event_id,
  ['signup','click','purchase','refund'][(number % 4) + 1]               AS event_type,
  round(((number % 50) + 1) + (number % 100) / 100.0, 2)                 AS amount,
  map('country', ['GB','US','DE','FR','IN'][(number % 5) + 1],
      'city',    ['London','NYC','Berlin','Paris','Mumbai'][(number % 5) + 1]) AS geo,
  arrayDistinct(arrayMap(i -> ['mobile','web','beta','vip'][((number + i) % 4) + 1],
    range((number % 3) + 1)))                                            AS tags
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.jsonl' TRUNCATE FORMAT JSONEachRow
"

# A genuine top-level JSON array ([{...},{...}]), wrapping the same rows.
# JSONEachRow reads both this and the line-delimited file above.
echo "Generating data/events.json ($SMALL_ROWS rows, top-level JSON array)..."
{ echo '['; sed '$!s/$/,/' data/events.jsonl; echo ']'; } > data/events.json

echo "Generating data/events.jsonl.gz..."
clickhouse local -q "SELECT * FROM file('data/events.jsonl', JSONEachRow) INTO OUTFILE 'data/events.jsonl.gz' TRUNCATE FORMAT JSONEachRow"

echo "Generating data/events_large.jsonl ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number + 1                                                                       AS event_id,
  ['signup','click','purchase','refund'][(rand(1) % 4) + 1]                        AS event_type,
  round((rand(2) % 50000) / 100.0, 2)                                              AS amount,
  map('country', ['GB','US','DE','FR','IN','BR','JP','CA','NL','AU'][(rand(3) % 10) + 1],
      'city',    ['London','NYC','Berlin','Paris','Mumbai'][(rand(4) % 5) + 1])    AS geo,
  ['mobile','web','beta','vip'][(rand(5) % 4) + 1]                                 AS tag
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo
echo "Generated files:"
ls -la data
