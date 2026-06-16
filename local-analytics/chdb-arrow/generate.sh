#!/usr/bin/env bash
# Generate a sample Arrow IPC file (.arrow) locally with clickhouse local.
# Idempotent. Override sizes: SMALL_ROWS (sample) / LARGE_ROWS (perf file).
set -euo pipefail
cd "$(dirname "$0")"

LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data
rm -f data/events.arrow

# Arrow IPC *file* format (FORMAT Arrow). Feather IS the Arrow IPC file format, so
# .arrow / .feather files written here are read by pyarrow.feather and chDB alike.
clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(cityHash64(number) % 5) + 1]            AS country,
  ['view','cart','purchase'][(cityHash64(number, 'e') % 3) + 1]       AS event_type,
  (cityHash64(number, 'q') % 10) + 1                                  AS quantity,
  round((cityHash64(number, 'a') % 100000) / 100.0, 2)               AS amount,
  toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 't') % 7776000) AS event_time
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events.arrow' FORMAT Arrow
"

echo "Wrote data/events.arrow ($(du -h data/events.arrow | cut -f1), ${LARGE_ROWS} rows)"
