#!/usr/bin/env bash
# The exact commands from the article "How to convert MsgPack to JSON".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# MsgPack has no embedded schema, so reads REQUIRE an explicit structure.
STRUCT='event_id UInt64, ts DateTime, event_type String, country String, amount Float64'

echo "== 1. Reading without a structure fails (MsgPack carries no schema) =="
clickhouse local -q "SELECT * FROM file('events.msgpack') LIMIT 1" 2>&1 | head -3 || true

echo
echo "== 2. Convert MsgPack -> JSON (one object per line, NDJSON) =="
clickhouse local -q "SELECT * FROM file('events.msgpack', MsgPack, '$STRUCT') INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
head -5 events.jsonl

echo
echo "== 3. Convert MsgPack -> JSON (single array document) =="
clickhouse local -q "SELECT * FROM file('events.msgpack', MsgPack, '$STRUCT') LIMIT 2 INTO OUTFILE 'events.json' TRUNCATE FORMAT JSON"
head -40 events.json

echo
echo "== 4. Filter / reshape during the conversion =="
clickhouse local -q "
SELECT event_id, ts, country, amount
FROM file('events.msgpack', MsgPack, '$STRUCT')
WHERE event_type = 'purchase'
ORDER BY amount DESC
LIMIT 3
FORMAT JSONEachRow
"

echo
echo "== 5. Perf: convert the 3M-row, ~93 MB events_large.msgpack (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.msgpack', MsgPack, '$STRUCT') INTO OUTFILE 'events_large.jsonl' TRUNCATE FORMAT JSONEachRow"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_mp_time.txt
  echo "run $i: $(grep real /tmp/_mp_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('events_large.jsonl', JSONEachRow)"
