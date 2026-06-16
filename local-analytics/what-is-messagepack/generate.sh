#!/usr/bin/env bash
# Generate a small demo MessagePack file locally with clickhouse local.
# MsgPack is a compact binary serialization; clickhouse local writes it natively.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-2000000}

SMALL="$(pwd)/data/events.msgpack"
LARGE="$(pwd)/data/events_large.msgpack"
JSONL="$(pwd)/data/events.jsonl"
rm -f "$SMALL" "$LARGE" "$JSONL"

# A small, human-checkable file (the one the article reads).
clickhouse local -q "
SELECT
    number AS id,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['mobile','desktop','tablet'][(number % 3) + 1] AS device,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue,
    toUInt8((number % 4) + 1) AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE '$SMALL'
FORMAT MsgPack
"

# The same rows as line-delimited JSON, for the size comparison in the article.
clickhouse local -q "
SELECT
    number AS id,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['mobile','desktop','tablet'][(number % 3) + 1] AS device,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue,
    toUInt8((number % 4) + 1) AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE '$JSONL'
FORMAT JSONEachRow
"

# A larger file for the honest perf number (kept modest).
clickhouse local -q "
SELECT
    number AS id,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['mobile','desktop','tablet'][(number % 3) + 1] AS device,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue,
    toUInt8((number % 4) + 1) AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE '$LARGE'
FORMAT MsgPack
"

ls -lh "$SMALL" "$JSONL" "$LARGE"
