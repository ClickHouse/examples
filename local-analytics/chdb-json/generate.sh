#!/usr/bin/env bash
# Generate the sample JSON files used by the read-json-file-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p data

# 1. Small, hand-shaped NDJSON with nested objects and arrays (for the examples).
cat > data/events.ndjson <<'JSON'
{"event_id": 1, "country": "GB", "event_type": "purchase", "revenue": 49.99, "user": {"id": 101, "tier": "gold"}, "items": ["sku-a", "sku-b"]}
{"event_id": 2, "country": "AU", "event_type": "view", "revenue": 0, "user": {"id": 102, "tier": "silver"}, "items": ["sku-c"]}
{"event_id": 3, "country": "GB", "event_type": "purchase", "revenue": 19.50, "user": {"id": 103, "tier": "gold"}, "items": ["sku-a"]}
{"event_id": 4, "country": "IN", "event_type": "purchase", "revenue": 5.00, "user": {"id": 104, "tier": "bronze"}, "items": ["sku-d", "sku-e", "sku-f"]}
{"event_id": 5, "country": "AU", "event_type": "purchase", "revenue": 99.00, "user": {"id": 105, "tier": "gold"}, "items": []}
JSON

# 2. The same first three rows as a single top-level JSON array (a regular .json).
cat > data/events_array.json <<'JSON'
[
  {"event_id": 1, "country": "GB", "event_type": "purchase", "revenue": 49.99, "user": {"id": 101, "tier": "gold"}, "items": ["sku-a", "sku-b"]},
  {"event_id": 2, "country": "AU", "event_type": "view", "revenue": 0, "user": {"id": 102, "tier": "silver"}, "items": ["sku-c"]},
  {"event_id": 3, "country": "GB", "event_type": "purchase", "revenue": 19.50, "user": {"id": 103, "tier": "gold"}, "items": ["sku-a"]}
]
JSON

# 3. Irregular NDJSON: rows with different keys (shows where the JSON type helps).
cat > data/events_irregular.ndjson <<'JSON'
{"id": 1, "type": "a", "props": {"color": "red"}}
{"id": 2, "type": "b", "props": {"weight": 5, "tags": ["x","y"]}}
{"id": 3, "type": "a", "extra_field": true}
JSON

# 4. A larger NDJSON file (2M rows, ~146 MB) for the performance contrast.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['purchase','view'][(number % 2) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS revenue
FROM numbers(2000000)
INTO OUTFILE 'data/events_2m.ndjson' TRUNCATE FORMAT JSONEachRow
"

echo "Generated:"
ls -lh data
