#!/usr/bin/env bash
# Generate the sample Feather files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.feather        - SMALL_ROWS rows (the worked example)
#   data/events_v1.feather     - legacy Feather V1, written by pyarrow (gotcha demo)
#   data/events_large.feather  - LARGE_ROWS rows (the perf number)
# Feather IS the Arrow IPC file format, so we write it with FORMAT Arrow.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/events.feather ($SMALL_ROWS rows) via FORMAT Arrow..."
clickhouse local -q "
SELECT
  toDateTime64('2026-01-01 00:00:00', 3, 'UTC') + (number * 3600)      AS event_time,
  number + 1                                                           AS event_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]                    AS country,
  ['click','view','purchase','refund'][(number % 4) + 1]              AS event_type,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)            AS revenue,
  (number % 5 + 1)::UInt8                                             AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/events.feather' TRUNCATE FORMAT Arrow
"

echo "Generating data/events_large.feather ($LARGE_ROWS rows) via FORMAT Arrow..."
clickhouse local -q "
SELECT
  toDateTime64('2026-01-01 00:00:00', 3, 'UTC') + (rand(1) % 31536000)           AS event_time,
  number + 1                                                                     AS event_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]        AS country,
  ['click','view','purchase','refund','signup'][(rand(3) % 5) + 1]              AS event_type,
  round((rand(4) % 50000) / 100.0, 2)                                           AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                       AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/events_large.feather' TRUNCATE FORMAT Arrow
"

# Legacy Feather V1 (the old FEA1 format), written by pyarrow if available.
# Used to show that ClickHouse's Arrow reader expects Feather V2 (Arrow IPC).
if python3 -c "import pyarrow.feather" 2>/dev/null; then
  echo "Generating data/events_v1.feather (legacy Feather V1) via pyarrow..."
  python3 - <<'PY'
import pyarrow.feather as feather, pyarrow as pa
t = pa.table({"event_id":[1,2,3],"country":["GB","US","DE"]})
feather.write_feather(t, "data/events_v1.feather", version=1)
PY
else
  echo "pyarrow not found; skipping legacy V1 sample (optional)."
fi

echo
echo "Generated files:"
ls -la data
