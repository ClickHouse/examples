#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-messagepack
set -euo pipefail
cd "$(dirname "$0")"
SMALL="$(pwd)/data/events.msgpack"
JSONL="$(pwd)/data/events.jsonl"
LARGE="$(pwd)/data/events_large.msgpack"
STRUCT='id UInt64, country String, device String, event_type String, revenue Float64, quantity UInt8'

if [[ ! -f "$SMALL" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Look at the raw bytes (compact binary, no field names per row) ==="
xxd "$SMALL" | head -4

echo
echo "=== 2. Read it: MsgPack carries NO schema, so the structure is required ==="
clickhouse local -q "
SELECT *
FROM file('$SMALL', MsgPack, '$STRUCT')
LIMIT 5
FORMAT Pretty"

echo
echo "=== 3. What happens without the structure ==="
clickhouse local -q "SELECT * FROM file('$SMALL', MsgPack) LIMIT 1" 2>&1 | head -3 || true

echo
echo "=== 4. Size on disk vs the same 20 rows as JSON ==="
printf 'events.msgpack  %5s bytes\n' "$(wc -c < "$SMALL")"
printf 'events.jsonl    %5s bytes\n' "$(wc -c < "$JSONL")"

echo
echo "=== 5. Aggregate over a 2,000,000-row MessagePack file ==="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue)) AS revenue
FROM file('$LARGE', MsgPack, '$STRUCT')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"
