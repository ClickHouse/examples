#!/usr/bin/env bash
# Generate the sample Avro files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/events.avro        - 8 rows, the worked example (plain Avro Object Container File)
#   data/events_large.avro  - 3,000,000 rows, ~62 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
#
# NOTE: clickhouse local writes plain Avro (the .avro Object Container File), which
# is what you read 99% of the time. The Confluent wire format (AvroConfluent) is a
# different, registry-bound framing produced by Kafka producers; it cannot be
# synthesised meaningfully without a live Schema Registry, so this folder proves the
# plain-Avro read and shows the AvroConfluent command form (see run.sh step 5).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.avro ($SMALL_ROWS rows)..."
clickhouse local -q "
SELECT
  toString(toDate('2026-01-01') + (number % 30))                       AS event_date,
  number + 1                                                           AS event_id,
  ['login','click','purchase','refund','logout'][(number % 5) + 1]    AS event_type,
  ['GB','US','DE','FR','IN'][(number % 5) + 1]                         AS country,
  (100000 + (number % 50000))::UInt32                                  AS user_id,
  round((number % 30000) / 100.0, 2)                                   AS amount
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.avro' TRUNCATE FORMAT Avro
"

echo "Generating data/events_large.avro ($LARGE_ROWS rows, ~62 MB)..."
clickhouse local -q "
SELECT
  toString(toDate('2026-01-01') + (rand(1) % 365))                              AS event_date,
  number + 1                                                                    AS event_id,
  ['login','click','purchase','refund','logout'][(rand(2) % 5) + 1]            AS event_type,
  ['GB','US','DE','FR','IN','BR','JP','NL'][(rand(3) % 8) + 1]                  AS country,
  (100000 + (rand(4) % 900000))::UInt32                                         AS user_id,
  round((rand(5) % 50000) / 100.0, 2)                                          AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.avro' TRUNCATE FORMAT Avro
"

echo
echo "Generated files:"
ls -la data
