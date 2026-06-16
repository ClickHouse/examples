#!/usr/bin/env bash
# Generate the sample NDJSON files used by the read-ndjson-file-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-2000000}

mkdir -p data

# 1. Small, hand-shaped NDJSON: one JSON object per line, nested object + array.
cat > data/events.ndjson <<'JSON'
{"event_id": 1, "country": "GB", "event_type": "purchase", "revenue": 49.99, "user": {"id": 101, "tier": "gold"}, "tags": ["web", "promo"]}
{"event_id": 2, "country": "AU", "event_type": "view", "revenue": 0, "user": {"id": 102, "tier": "silver"}, "tags": ["app"]}
{"event_id": 3, "country": "GB", "event_type": "purchase", "revenue": 19.50, "user": {"id": 103, "tier": "gold"}, "tags": ["web"]}
{"event_id": 4, "country": "IN", "event_type": "purchase", "revenue": 5.00, "user": {"id": 104, "tier": "bronze"}, "tags": ["app", "promo", "ref"]}
{"event_id": 5, "country": "AU", "event_type": "purchase", "revenue": 99.00, "user": {"id": 105, "tier": "gold"}, "tags": []}
JSON

# 2. The exact same data with a .jsonl extension: ndjson == jsonl, identical bytes.
cp data/events.ndjson data/events.jsonl

# 3. A larger NDJSON file for the performance contrast vs pure Python.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['purchase','view'][(number % 2) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS revenue
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events_large.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generated:"
ls -lh data
