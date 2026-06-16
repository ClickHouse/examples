#!/usr/bin/env bash
# Generate the sample Arrow IPC files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.arrow        - SMALL_ROWS rows, Arrow IPC *file* format (FORMAT Arrow)
#   data/events_stream.arrow - SMALL_ROWS rows, Arrow IPC *streaming* format (FORMAT ArrowStream)
#   data/events_large.arrow  - LARGE_ROWS rows (~the perf number), Arrow IPC file format
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# A row generator reused for every file. Note the typed columns: Arrow carries
# real types (no Nullable wrapper, no text re-parsing), which is the whole point.
read -r -d '' SELECT <<'SQL' || true
SELECT
  toDate('2026-01-01') + (number % 30)                                AS event_date,
  (number + 1)::UInt32                                                AS event_id,
  ['signup','login','purchase','refund','logout'][(number % 5) + 1]  AS event_type,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(number % 10) + 1] AS country,
  round((number % 50000) / 100.0, 2)                                  AS amount,
  (number % 4 = 0)                                                    AS is_member
FROM numbers(__ROWS__)
SQL

echo "Generating data/events.arrow ($SMALL_ROWS rows, Arrow IPC file format)..."
clickhouse local -q "${SELECT/__ROWS__/$SMALL_ROWS} INTO OUTFILE 'data/events.arrow' TRUNCATE FORMAT Arrow"

echo "Generating data/events_stream.arrow ($SMALL_ROWS rows, Arrow IPC streaming format)..."
clickhouse local -q "${SELECT/__ROWS__/$SMALL_ROWS} INTO OUTFILE 'data/events_stream.arrow' TRUNCATE FORMAT ArrowStream"

echo "Generating data/events_large.arrow ($LARGE_ROWS rows, Arrow IPC file format)..."
clickhouse local -q "${SELECT/__ROWS__/$LARGE_ROWS} INTO OUTFILE 'data/events_large.arrow' TRUNCATE FORMAT Arrow"

echo
echo "Generated files:"
ls -la data
