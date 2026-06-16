#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-protobuf
# Protobuf is schema-first. Every read passes the same .proto via
# SETTINGS format_schema = 'events.proto:Event'.
set -euo pipefail
cd "$(dirname "$0")"

SCHEMA="$(pwd)/events.proto:Event"
FILE="$(pwd)/data/events.bin"

if [[ ! -f "$FILE" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Read without a schema (Protobuf has none embedded) ==="
clickhouse local -q "SELECT count() FROM file('$FILE', Protobuf)" 2>&1 | head -1 || true

echo
echo "=== 2. Read WITH the .proto schema ==="
clickhouse local -q "
SELECT *
FROM file('$FILE', Protobuf)
ORDER BY id
LIMIT 5
SETTINGS format_schema = '$SCHEMA'
FORMAT Pretty"

echo
echo "=== 3. DESCRIBE: columns + types are derived from the .proto ==="
clickhouse local -q "
DESCRIBE file('$FILE', Protobuf)
SETTINGS format_schema = '$SCHEMA'
FORMAT PrettyCompactNoEscapes"

echo
echo "=== 4. Query it like a table (filter + aggregate) ==="
clickhouse local -q "
SELECT country, count() AS purchases, round(sum(revenue)) AS revenue
FROM file('$FILE', Protobuf)
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
SETTINGS format_schema = '$SCHEMA'
FORMAT Pretty"

echo
echo "=== 5. The wire format: length-prefixed binary, no field names on the wire ==="
clickhouse local -q "SELECT hex(substring(file('$FILE'), 1, 32)) AS first_32_bytes FORMAT Vertical"
