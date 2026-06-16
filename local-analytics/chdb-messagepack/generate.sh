#!/usr/bin/env bash
# Generate the sample MsgPack files used by the read-messagepack-file-python how-to.
# Everything is created locally with `clickhouse local`. Idempotent: re-running overwrites.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data

# 1. Small MsgPack file for the worked examples.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
  ['purchase','view'][(number % 2) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS amount
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/events.msgpack' TRUNCATE FORMAT MsgPack
"

# 2. A larger MsgPack file (default 3M rows, ~90 MB) for the performance contrast.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
  ['purchase','view'][(number % 2) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS amount
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events_large.msgpack' TRUNCATE FORMAT MsgPack
"

echo "Generated:"
ls -lh data
