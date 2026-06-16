#!/usr/bin/env bash
# Generate a small demo ORC file locally with clickhouse local.
# Deterministic structure: 1,000,000 rows, 7 columns, ZSTD, 10k row-index stride.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data
OUT="$(pwd)/data/events.orc"
LARGE_ROWS=${LARGE_ROWS:-1000000}
rm -f "$OUT"

clickhouse local -q "
SELECT
    number AS id,
    toDateTime('2026-01-01 00:00:00') + toIntervalMinute(number) AS event_time,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['mobile','desktop','tablet'][(number % 3) + 1] AS device,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue,
    toUInt8((number % 4) + 1) AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE '$OUT'
FORMAT ORC
"

ls -lh "$OUT"
