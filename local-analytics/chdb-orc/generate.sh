#!/usr/bin/env bash
# Generate a sample ORC file locally with clickhouse local.
# Idempotent: removes any existing file first.
# Row count overridable: LARGE_ROWS=3000000 ./generate.sh
set -euo pipefail
cd "$(dirname "$0")"

LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data
rm -f data/events.orc

clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(cityHash64(number) % 5) + 1]            AS country,
  ['view','cart','purchase'][(cityHash64(number, 'e') % 3) + 1]       AS event_type,
  (cityHash64(number, 'q') % 10) + 1                                  AS quantity,
  round((cityHash64(number, 'a') % 100000) / 100.0, 2)               AS amount,
  toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 't') % 7776000) AS event_time
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events.orc' FORMAT ORC
"

echo "Wrote data/events.orc ($(du -h data/events.orc | cut -f1), ${LARGE_ROWS} rows)"
