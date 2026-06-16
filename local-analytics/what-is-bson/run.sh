#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-bson
set -euo pipefail
cd "$(dirname "$0")"
USERS="$(pwd)/data/users.bson"
EVENTS="$(pwd)/data/events.bson"

if [[ ! -f "$USERS" || ! -f "$EVENTS" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Read the BSON file (schema inferred from the typed fields) ==="
clickhouse local -q "
SELECT * FROM file('$USERS', BSONEachRow)
FORMAT Pretty"

echo
echo "=== 2. BSON carries its own types -> DESCRIBE infers the schema ==="
clickhouse local -q "
DESCRIBE file('$USERS', BSONEachRow)
FORMAT Pretty"

echo
echo "=== 3. The bytes: length-prefixed document, one type byte per field ==="
echo "(first 0x68 = 104 bytes = the first document's length, little-endian)"
xxd "$USERS" | head -7

echo
echo "=== 4. Query it like any table: filter + aggregate ==="
clickhouse local -q "
SELECT country, count() AS users, round(avg(balance), 2) AS avg_balance
FROM file('$USERS', BSONEachRow)
GROUP BY country
ORDER BY country
FORMAT Pretty"

echo
echo "=== 5. Read-throughput over a larger BSON file (1.5M rows) ==="
clickhouse local --time -q "
SELECT event_type, count() AS n, round(sum(amount)) AS total
FROM file('$EVENTS', BSONEachRow)
GROUP BY event_type
ORDER BY event_type
FORMAT Pretty"
