#!/usr/bin/env bash
# Generate a sample Feather file (Arrow IPC) locally with clickhouse local.
# Feather IS the Arrow IPC format, so we write it with FORMAT Arrow.
# Idempotent: removes any existing file first.
# Row count override: LARGE_ROWS=... ./generate.sh  (default 3,000,000).
set -euo pipefail
cd "$(dirname "$0")"

LARGE_ROWS=${LARGE_ROWS:-3000000}

rm -f events.feather

clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(cityHash64(number) % 5) + 1]            AS country,
  ['view','cart','purchase'][(cityHash64(number, 'e') % 3) + 1]       AS event_type,
  toUInt8((cityHash64(number, 'q') % 10) + 1)                         AS quantity,
  round((cityHash64(number, 'a') % 100000) / 100.0, 2)               AS amount,
  toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 't') % 7776000) AS event_time
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'events.feather' FORMAT Arrow
"

echo "Wrote events.feather ($(du -h events.feather | cut -f1), ${LARGE_ROWS} rows)"
