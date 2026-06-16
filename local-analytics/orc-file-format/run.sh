#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/orc-file-format
set -euo pipefail
cd "$(dirname "$0")"
FILE="$(pwd)/data/events.orc"

if [[ ! -f "$FILE" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Schema, inferred straight from the ORC file ==="
clickhouse local -q "DESCRIBE file('$FILE') FORMAT Pretty"

echo
echo "=== 2. Read the ORC file (filter + aggregate) ==="
clickhouse local -q "
SELECT country, count() AS purchases, round(sum(revenue)) AS revenue
FROM file('$FILE')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"

echo
echo "=== 3. Crack the ORC footer with a standard ORC reader (pyarrow) ==="
echo "    (ClickHouse reads ORC data natively but has no ORC-metadata FORMAT)"
python3 footer.py "$FILE"
