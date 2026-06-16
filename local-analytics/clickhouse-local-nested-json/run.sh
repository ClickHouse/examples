#!/usr/bin/env bash
# The exact commands from the article "How to query nested JSON with SQL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read the first rows (nested objects auto-detected) =="
clickhouse local -q "SELECT * FROM file('events.jsonl') LIMIT 2 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the inferred nested schema =="
clickhouse local -q "DESCRIBE file('events.jsonl')" \
  | awk -F'\t' '{gsub(/\\n/," ",$2); gsub(/  +/," ",$2); print $1": "$2}'

echo
echo "== 3. Dot access into nested objects (user.geo.country) =="
clickhouse local -q "
SELECT event_id, user.name, user.geo.country, user.geo.city
FROM file('events.jsonl')
FORMAT PrettyCompact"

echo
echo "== 4. Explode a nested array with ARRAY JOIN =="
clickhouse local -q "
SELECT event_id, item.sku AS sku, item.qty AS qty, item.price AS price
FROM file('events.jsonl')
ARRAY JOIN items AS item
FORMAT PrettyCompact"

echo
echo "== 5. Aggregate across the exploded line items =="
clickhouse local -q "
SELECT item.sku AS sku, sum(item.qty) AS units, round(sum(item.qty * item.price), 2) AS revenue
FROM file('events.jsonl')
ARRAY JOIN items AS item
GROUP BY sku
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 6. Irregular keys: read props as raw JSON text, pull keys with JSONExtract* =="
clickhouse local -q "
SELECT
  event_type,
  JSONExtractString(props, 'gateway') AS gateway,
  JSONExtractString(props, 'reason')  AS refund_reason,
  JSONExtractBool(props, 'mfa')       AS mfa
FROM file('events.jsonl', 'JSONEachRow',
  'event_id UInt32, event_type String, props String')
FORMAT PrettyCompact"

echo
echo "== 7. Irregular keys, the native way: read props as the JSON type =="
clickhouse local -q "
SELECT
  event_type,
  props.gateway      AS gateway,
  props.installments AS installments,
  props.reason       AS refund_reason
FROM file('events.jsonl', 'JSONEachRow',
  'event_id UInt32, event_type String, props JSON')
SETTINGS enable_json_type = 1
FORMAT PrettyCompact"

echo
echo "== 8. Read the whole document as one JSON column with JSONAsObject =="
clickhouse local -q "
SELECT json.event_type, json.user.geo.country AS country, json.user.name AS name
FROM file('events.jsonl', JSONAsObject, 'json JSON')
SETTINGS enable_json_type = 1
FORMAT PrettyCompact"

echo
echo "== 9. Read a gzipped JSONL transparently (.jsonl.gz) =="
clickhouse local -q "
SELECT user.geo.country AS country, count() AS events
FROM file('events.jsonl.gz', JSONEachRow)
GROUP BY country ORDER BY country
FORMAT PrettyCompact"

echo
echo "== 10. Perf: explode + group-by on the 500k-row, ~137 MB events_large.jsonl (best-of-3, warm) =="
Q="SELECT user.geo.country AS country, item.sku AS sku, sum(item.qty) AS units, round(sum(item.qty*item.price),2) AS revenue FROM file('events_large.jsonl') ARRAY JOIN items AS item GROUP BY country, sku ORDER BY revenue DESC LIMIT 5"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_nj_time.txt
  echo "run $i: $(grep real /tmp/_nj_time.txt)"
done
clickhouse local -q "$Q FORMAT PrettyCompact"
