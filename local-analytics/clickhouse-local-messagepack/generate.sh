#!/usr/bin/env bash
# Generate the sample MsgPack files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.msgpack        - 20 rows (the worked example)
#   data/events_large.msgpack  - 3,000,000 rows (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.msgpack ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  (number + 1)::UInt64                                                  AS id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                     AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]               AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)::Float64     AS revenue,
  (number % 5 + 1)::UInt8                                              AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.msgpack' TRUNCATE FORMAT MsgPack
"

echo "Generating data/events_large.msgpack ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  (number + 1)::UInt64                                                          AS id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','view','purchase','refund'][(rand(3) % 4) + 1]                        AS event_type,
  round((rand(4) % 50000) / 100.0, 2)::Float64                                   AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                       AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.msgpack' TRUNCATE FORMAT MsgPack
"

echo "Generating data/events.msgpack.gz (transparent compression demo)..."
clickhouse local -q "
SELECT id, country, event_type, revenue, quantity
FROM file('data/events.msgpack', MsgPack, 'id UInt64, country String, event_type String, revenue Float64, quantity UInt8')
INTO OUTFILE 'data/events.msgpack.gz' TRUNCATE FORMAT MsgPack
"

echo
echo "Generated files:"
ls -la data
