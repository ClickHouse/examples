#!/usr/bin/env bash
# Generate a small demo BSON file locally with clickhouse local.
# BSON = Binary JSON (MongoDB's storage/interchange format): typed, length-prefixed.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-1500000}

SMALL="$(pwd)/data/users.bson"
LARGE="$(pwd)/data/events.bson"
rm -f "$SMALL" "$LARGE"

# Small, human-inspectable file: a handful of typed user documents.
clickhouse local -q "
SELECT
    number AS user_id,
    ['alice','bob','carol','dave','erin'][(number % 5) + 1] AS name,
    ['GB','US','DE','FR','IN'][(number % 5) + 1] AS country,
    toDateTime('2026-01-01 00:00:00') + toIntervalHour(number) AS signup_time,
    round(randUniform(1, 1000), 2) AS balance,
    (number % 2 = 0) AS active
FROM numbers(${SMALL_ROWS})
INTO OUTFILE '$SMALL'
FORMAT BSONEachRow
"

# Larger file for an honest read-throughput number.
clickhouse local -q "
SELECT
    number AS event_id,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    ['GB','US','DE','FR','IN'][(number % 5) + 1] AS country,
    round(randUniform(1, 500), 2) AS amount
FROM numbers(${LARGE_ROWS})
INTO OUTFILE '$LARGE'
FORMAT BSONEachRow
"

ls -lh "$SMALL" "$LARGE"
