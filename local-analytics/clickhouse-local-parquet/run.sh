#!/usr/bin/env bash
# The exact commands from the article. Run ./generate.sh first.
set -euo pipefail
cd "$(dirname "$0")"
DATA_DIR="${1:-data}"

echo "=== View the first rows (no schema, no import) ==="
clickhouse local -q "SELECT * FROM file('$DATA_DIR/data.parquet') LIMIT 5 FORMAT PrettyCompact"

echo
echo "=== Inferred schema ==="
clickhouse local -q "DESCRIBE file('$DATA_DIR/data.parquet') FORMAT PrettyCompact"

echo
echo "=== Filter + aggregate + group by ==="
clickhouse local -q "
SELECT country,
       count() AS purchases,
       round(sum(revenue), 2) AS revenue,
       round(avg(quantity), 3) AS avg_qty
FROM file('$DATA_DIR/data.parquet')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
LIMIT 5
FORMAT PrettyCompact"

echo
echo "=== Read a zstd-compressed Parquet file (no flags needed) ==="
clickhouse local -q "SELECT count(), round(sum(revenue), 2) FROM file('$DATA_DIR/data.zstd.parquet') FORMAT PrettyCompact"

echo
echo "=== Perf: aggregate the ~1 GB file (best of 3, warm cache) ==="
Q="SELECT country, count() AS purchases, round(sum(revenue),2) AS revenue, round(avg(quantity),3) AS avg_qty FROM file('$DATA_DIR/events_large.parquet') WHERE event_type='purchase' GROUP BY country ORDER BY revenue DESC"
clickhouse local -q "$Q" >/dev/null 2>&1   # warm the page cache
for i in 1 2 3; do
  echo -n "run $i: "; clickhouse local -q "$Q FORMAT Null" --time
done
