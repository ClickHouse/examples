#!/usr/bin/env bash
# Generate a 20M-row (~260 MB) sample Parquet file locally with clickhouse local.
# Idempotent: removes any existing file first.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p data
rm -f data/events.parquet

clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(cityHash64(number) % 5) + 1]            AS country,
  ['view','cart','purchase'][(cityHash64(number, 'e') % 3) + 1]       AS event_type,
  (cityHash64(number, 'q') % 10) + 1                                  AS quantity,
  round((cityHash64(number, 'a') % 100000) / 100.0, 2)               AS amount,
  toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 't') % 7776000) AS event_time
FROM numbers(20000000)
INTO OUTFILE 'data/events.parquet' FORMAT Parquet
"

echo "Wrote data/events.parquet ($(du -h data/events.parquet | cut -f1))"
