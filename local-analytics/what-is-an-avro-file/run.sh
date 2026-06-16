#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-an-avro-file
set -euo pipefail
cd "$(dirname "$0")"
V1="$(pwd)/data/events_v1.avro"
V2="$(pwd)/data/events_v2.avro"
BIG="$(pwd)/data/events_big.avro"

if [[ ! -f "$V1" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Read the Avro file (schema inferred from the embedded header) ==="
clickhouse local -q "DESCRIBE file('$V1')"

echo
echo "=== 2. Read the embedded JSON schema straight out of the file header ==="
clickhouse local -q "
SELECT extractGroups(raw, '(\{\"type\":\"record\".*?\}\]\})')[1] AS avro_schema
FROM file('$V1', RawBLOB, 'raw String')
FORMAT TSVRaw" | python3 -m json.tool

echo
echo "=== 3. Query the file directly: revenue by country ==="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue)) AS revenue
FROM file('$V1')
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"

echo
echo "=== 4. Schema evolution: v2 added a 'channel' column ==="
echo "--- v2 embedded schema ---"
clickhouse local -q "
SELECT extractGroups(raw, '(\{\"type\":\"record\".*?\}\]\})')[1] AS avro_schema
FROM file('$V2', RawBLOB, 'raw String')
FORMAT TSVRaw" | python3 -m json.tool

echo "--- each file is self-describing: v2 reads its own schema, new column included ---"
clickhouse local -q "
SELECT channel, count() AS events, round(sum(revenue)) AS revenue
FROM file('$V2')
GROUP BY channel
ORDER BY channel
FORMAT Pretty"
