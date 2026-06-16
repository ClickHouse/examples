#!/usr/bin/env bash
# Generate demo NDJSON / JSON Lines data locally with clickhouse local.
# Writes:
#   data/events.ndjson       - small, human-readable, one JSON object per line
#   data/events_array.json   - the SAME rows as a single JSON array document (for contrast)
#   data/events_large.ndjson - a modest perf file
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-1500000}

SMALL="$(pwd)/data/events.ndjson"
ARRAY="$(pwd)/data/events_array.json"
LARGE="$(pwd)/data/events_large.ndjson"
rm -f "$SMALL" "$ARRAY" "$LARGE"

emit_rows () {  # $1 = row count
  clickhouse local -q "
SELECT
    number AS id,
    toDateTime('2026-01-01 00:00:00') + toIntervalMinute(number) AS event_time,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue
FROM numbers($1)
FORMAT JSONEachRow"
}

# Small NDJSON: one JSON object per line.
emit_rows "$SMALL_ROWS" > "$SMALL"

# The SAME rows as a single JSON array document, for the NDJSON-vs-array contrast.
emit_rows "$SMALL_ROWS" \
  | python3 -c "import sys,json; print(json.dumps([json.loads(l) for l in sys.stdin if l.strip()], indent=2))" \
  > "$ARRAY"

# Large NDJSON for a modest perf number.
emit_rows "$LARGE_ROWS" > "$LARGE"

echo "Wrote:"
ls -lh "$SMALL" "$ARRAY" "$LARGE"
echo
echo "First 3 lines of the NDJSON file (one object per line):"
head -n 3 "$SMALL"
