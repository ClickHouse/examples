#!/usr/bin/env bash
# Generate the sample JSONL files used by the read-jsonl-file-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p data

# Row counts are overridable so a verifier can run fast:
#   SMALL_ROWS=20 LARGE_ROWS=100000 ./generate.sh
LARGE_ROWS="${LARGE_ROWS:-2000000}"

# 1. Small, hand-shaped JSONL (.jsonl) with a nested object and an array.
#    JSONL / json-lines = one JSON object per line (identical wire format to NDJSON).
cat > data/orders.jsonl <<'JSON'
{"order_id": 1, "country": "GB", "status": "paid", "amount": 49.99, "customer": {"id": 101, "tier": "gold"}, "skus": ["sku-a", "sku-b"]}
{"order_id": 2, "country": "AU", "status": "cart", "amount": 0, "customer": {"id": 102, "tier": "silver"}, "skus": ["sku-c"]}
{"order_id": 3, "country": "GB", "status": "paid", "amount": 19.50, "customer": {"id": 103, "tier": "gold"}, "skus": ["sku-a"]}
{"order_id": 4, "country": "IN", "status": "paid", "amount": 5.00, "customer": {"id": 104, "tier": "bronze"}, "skus": ["sku-d", "sku-e", "sku-f"]}
{"order_id": 5, "country": "AU", "status": "paid", "amount": 99.00, "customer": {"id": 105, "tier": "gold"}, "skus": []}
JSON

# 2. A larger JSONL file (default 2M rows, ~150 MB) for the chDB-vs-pandas contrast.
clickhouse local -q "
SELECT
  number AS order_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['paid','cart'][(number % 2) + 1] AS status,
  round(randUniform(1, 100), 2) AS amount
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/orders_large.jsonl' TRUNCATE FORMAT JSONEachRow
"

echo "Generated:"
ls -lh data
