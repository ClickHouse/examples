#!/usr/bin/env bash
# Generate the sample nested-JSON files used by the flatten-nested-json-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-4}
LARGE_ROWS=${LARGE_ROWS:-800000}

mkdir -p data

# 1. Small, hand-shaped NDJSON: each order has a nested customer object and an
#    array of nested line-item objects. This is the shape we flatten in the article.
cat > data/orders.ndjson <<'JSON'
{"order_id": 1, "customer": {"id": 101, "country": "GB", "tier": "gold"}, "items": [{"sku": "A-1", "qty": 2, "price": 9.99}, {"sku": "B-2", "qty": 1, "price": 19.50}]}
{"order_id": 2, "customer": {"id": 102, "country": "AU", "tier": "silver"}, "items": [{"sku": "C-3", "qty": 5, "price": 4.00}]}
{"order_id": 3, "customer": {"id": 103, "country": "GB", "tier": "gold"}, "items": [{"sku": "A-1", "qty": 1, "price": 9.99}, {"sku": "D-4", "qty": 3, "price": 2.50}, {"sku": "E-5", "qty": 1, "price": 99.00}]}
{"order_id": 4, "customer": {"id": 104, "country": "IN", "tier": "bronze"}, "items": []}
JSON

# 2. JSON array version of the small file (used by the Python / chdb.datastore examples).
python3 -c "
import json, sys
records = [json.loads(l) for l in open('data/orders.ndjson')]
with open('data/orders.json', 'w') as f:
    json.dump(records, f, indent=1)
"

# 3. A larger NDJSON file (orders with nested customer + array of line items)
#    for the performance contrast vs pandas json_normalize. Named tuples make
#    JSONEachRow emit real nested objects with numeric qty/price (not strings).
clickhouse local -q "
SELECT
  number AS order_id,
  tuple(
    100000 + number,
    ['GB','AU','IN','US','DE'][(number % 5) + 1],
    ['gold','silver','bronze'][(number % 3) + 1]
  )::Tuple(id UInt32, country String, tier String) AS customer,
  arrayMap(i -> tuple(
      concat(['A','B','C','D','E'][(i % 5) + 1], '-', toString(number * 4 + i)),
      toUInt8((i % 5) + 1),
      round(randUniform(1, 100), 2)
    )::Tuple(sku String, qty UInt8, price Float64), range((number % 4) + 1)) AS items
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/orders_large.ndjson' TRUNCATE FORMAT JSONEachRow
SETTINGS output_format_json_quote_64bit_integers = 0
"

# 4. JSON array version of the large file (used by the perf contrast in run.py).
python3 -c "
import json
records = [json.loads(l) for l in open('data/orders_large.ndjson')]
with open('data/orders_large.json', 'w') as f:
    json.dump(records, f)
print('Converted orders_large.ndjson -> orders_large.json')
"

echo "Generated:"
ls -lh data
