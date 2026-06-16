#!/usr/bin/env bash
# Generate small demo Avro files locally with clickhouse local.
# Avro is row-oriented and embeds its JSON schema in the file header.
# We write two files to demonstrate schema evolution:
#   events_v1.avro  -> id, event_time, country, revenue
#   events_v2.avro  -> same + an added "channel" column
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-1000}
LARGE_ROWS=${LARGE_ROWS:-3000000}

V1="$(pwd)/data/events_v1.avro"
V2="$(pwd)/data/events_v2.avro"
BIG="$(pwd)/data/events_big.avro"
rm -f "$V1" "$V2" "$BIG"

# v1 schema
clickhouse local -q "
SELECT
    number AS id,
    toDateTime('2026-01-01 00:00:00') + toIntervalMinute(number) AS event_time,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    round(randUniform(1, 500), 2) AS revenue
FROM numbers($SMALL_ROWS)
INTO OUTFILE '$V1'
FORMAT Avro
"

# v2 schema: a "channel" field added to the record. Same data shape otherwise.
clickhouse local -q "
SELECT
    number AS id,
    toDateTime('2026-01-01 00:00:00') + toIntervalMinute(number) AS event_time,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    round(randUniform(1, 500), 2) AS revenue,
    ['organic','paid','referral'][(number % 3) + 1] AS channel
FROM numbers($SMALL_ROWS)
INTO OUTFILE '$V2'
FORMAT Avro
"

# Larger file for an honest read-throughput number. Modest by default.
clickhouse local -q "
SELECT
    number AS id,
    toDateTime('2026-01-01 00:00:00') + toIntervalMinute(number) AS event_time,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    round(randUniform(1, 500), 2) AS revenue
FROM numbers($LARGE_ROWS)
INTO OUTFILE '$BIG'
FORMAT Avro
"

ls -lh "$V1" "$V2" "$BIG"
