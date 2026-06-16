#!/usr/bin/env bash
# Generate the sample BSON files used by the read-bson-file-python how-to.
# Everything is created locally with `clickhouse local` (BSONEachRow output),
# so nothing large is committed to git. Idempotent: re-running overwrites.
#
# ClickHouse's BSONEachRow writes standard MongoDB-compatible BSON, the same
# layout `mongoexport --type=bson` / `mongodump` produces, so these stand in
# for a real .bson export.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-6}
LARGE_ROWS=${LARGE_ROWS:-2000000}

mkdir -p data

# 1. Small, flat collection of events (the core read/aggregate examples).
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['purchase','view','cart'][(number % 3) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS revenue
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/events.bson' TRUNCATE FORMAT BSONEachRow
"

# 2. A collection with a nested sub-document (a real Mongo-style shape) to show
#    the field-name gotcha: BSON sub-documents need explicit structure to name.
clickhouse local -q "
SELECT
  number AS order_id,
  tuple(toUInt32(100 + number) AS id, ['gold','silver','bronze'][(number % 3) + 1] AS tier) AS customer,
  round(randUniform(5, 500), 2) AS total
FROM numbers(4)
INTO OUTFILE 'data/orders.bson' TRUNCATE FORMAT BSONEachRow
"

# 3. A larger flat collection for the chDB-vs-pymongo performance contrast.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['purchase','view','cart'][(number % 3) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS revenue
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events_large.bson' TRUNCATE FORMAT BSONEachRow
"

echo "Generated:"
ls -lh data
