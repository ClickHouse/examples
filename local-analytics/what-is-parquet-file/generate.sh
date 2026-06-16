#!/usr/bin/env bash
# Generate a small demo Parquet file locally with clickhouse local.
# Deterministic structure: 2,000,000 rows, 7 columns, 4 row groups.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data
OUT="$(pwd)/data/events.parquet"
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
FROM numbers(2000000)
INTO OUTFILE '$OUT'
FORMAT Parquet
SETTINGS output_format_parquet_row_group_size = 500000
"

ls -lh "$OUT"
