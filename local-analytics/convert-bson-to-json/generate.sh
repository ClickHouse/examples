#!/usr/bin/env bash
# Generate sample BSON locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/users.bson        - SMALL_ROWS rows, nested document + array (the worked example)
#   data/events.bson       - LARGE_ROWS rows, flat-ish (the perf number)
# BSON here stands in for a MongoDB collection dump (`mongoexport --type=bson`
# / a `*.bson` file from `mongodump`). BSONEachRow writes one BSON document
# per row, which is exactly that shape.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-6}
LARGE_ROWS=${LARGE_ROWS:-2000000}

echo "Generating data/users.bson ($SMALL_ROWS docs, with a nested address + tags array)..."
clickhouse local -q "
SELECT
  number + 1                                                       AS _id,
  ['Ada','Lin','Tor','Mae','Ravi','Yuki'][(number % 6) + 1]        AS name,
  ['NYC','SF','LDN','BLR','TYO','BER'][(number % 6) + 1]           AS city,
  map(
    'street', concat(toString((number * 7) % 900 + 1), ' Market St'),
    'zip',    leftPad(toString((number * 137) % 99999), 5, '0')
  )                                                                AS address,
  arraySlice(['mongo','etl','beta','vip','trial'], 1, (number % 3) + 1) AS tags,
  toBool(number % 2)                                               AS active
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/users.bson' TRUNCATE FORMAT BSONEachRow
"

echo "Generating data/events.bson ($LARGE_ROWS docs, ~flat) for the perf number..."
clickhouse local -q "
SELECT
  number + 1                                                                  AS _id,
  (rand(1) % 50000) + 1                                                        AS user_id,
  ['click','view','signup','purchase','logout'][(rand(2) % 5) + 1]            AS event,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(3) % 10) + 1]      AS country,
  round((rand(4) % 50000) / 100.0, 2)                                         AS amount
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events.bson' TRUNCATE FORMAT BSONEachRow
"

echo
echo "Generated files:"
ls -la data
