#!/usr/bin/env bash
# Generate sample BSON locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/events.bson        - 20 rows, nested document (the worked example)
#   data/events_large.bson  - 1,300,000 rows, ~140 MB (the perf number)
# BSON is MongoDB's binary JSON; FORMAT BSONEachRow is the on-disk shape that
# `mongoexport` produces. Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-1300000}

# A MongoDB-style document: scalar fields plus a nested `geo` sub-document with
# named keys (country, sessions). Mixed field types make BSON keep it a real
# sub-document, so it infers back as a named Tuple you address as geo.country.
echo "Generating data/events.bson ($SMALL_ROWS rows, nested document)..."
clickhouse local -q "
SELECT
  number AS _id,
  ['alice','bob','carol','dave'][(number % 4) + 1]                      AS user,
  ['view','click','purchase','refund'][(number % 4) + 1]               AS event,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)              AS amount,
  CAST(tuple(
    ['GB','US','DE','FR','IN'][(number % 5) + 1],
    toInt32((number % 3) + 1)
  ), 'Tuple(country String, sessions Int32)')                           AS geo
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.bson' TRUNCATE FORMAT BSONEachRow
"

echo "Generating data/events_large.bson ($LARGE_ROWS rows)..."
clickhouse local -q "
SELECT
  number AS _id,
  ['alice','bob','carol','dave'][(rand(1) % 4) + 1]                     AS user,
  ['view','click','purchase','refund'][(rand(2) % 4) + 1]             AS event,
  round((rand(3) % 50000) / 100.0, 2)                                 AS amount,
  CAST(tuple(
    ['GB','US','DE','FR','IN'][(rand(4) % 5) + 1],
    toInt32((rand(5) % 3) + 1)
  ), 'Tuple(country String, sessions Int32)')                          AS geo
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.bson' TRUNCATE FORMAT BSONEachRow
"

echo
echo "Generated files:"
ls -la data
