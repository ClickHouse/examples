#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-ndjson
set -euo pipefail
cd "$(dirname "$0")"
NDJSON="$(pwd)/data/events.ndjson"
ARRAY="$(pwd)/data/events_array.json"

if [[ ! -f "$NDJSON" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. One JSON object per line (this is NDJSON) ==="
head -n 3 "$NDJSON"

echo
echo "=== 2. JSONEachRow infers the schema straight from the file ==="
clickhouse local -q "DESCRIBE file('$NDJSON', JSONEachRow) FORMAT Pretty"

echo
echo "=== 3. Query it like a table (no load step) ==="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue)) AS revenue
FROM file('$NDJSON', JSONEachRow)
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"

echo
echo "=== 4. The SAME data as a single JSON array document ==="
head -n 8 "$ARRAY"

echo
echo "=== 5. JSONEachRow reads that top-level array too (same query, array file) ==="
clickhouse local -q "
SELECT country, count() AS events
FROM file('$ARRAY', JSONEachRow)
GROUP BY country
ORDER BY country
FORMAT Pretty"

echo
echo "=== 6. NDJSON streams: pipe just the first 100 lines, no full-file parse ==="
head -n 100 "$(pwd)/data/events_large.ndjson" | clickhouse local -q "
SELECT count() AS rows, max(revenue) AS max_revenue
FROM file('-', JSONEachRow)
FORMAT Pretty"
