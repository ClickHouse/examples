#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-a-tsv-file
set -euo pipefail
cd "$(dirname "$0")"
TSV="$(pwd)/data/events.tsv"
CSV="$(pwd)/data/events.csv"

if [[ ! -f "$TSV" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. The raw bytes: tabs shown as -> ==="
sed 's/\t/->/g' "$TSV"

echo
echo "=== 2. clickhouse local infers the schema from the header (DESCRIBE) ==="
clickhouse local -q "
DESCRIBE file('$TSV', TSVWithNames)
FORMAT PrettyCompactMonoBlock"

echo
echo "=== 3. Query the TSV in place (filter + aggregate) ==="
clickhouse local -q "
SELECT country, count() AS events, round(sum(revenue), 2) AS revenue
FROM file('$TSV', TSVWithNames)
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"

echo
echo "=== 4. Contrast: a CSV needs quoting/escaping; a tab delimiter does not ==="
echo "--- raw CSV (one quoted field holds a comma AND an escaped quote) ---"
cat "$CSV"
echo "--- ClickHouse parses the quoting correctly ---"
clickhouse local -q "
SELECT id, country, label
FROM file('$CSV', CSVWithNames)
WHERE id = 7
FORMAT Vertical"
