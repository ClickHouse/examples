#!/usr/bin/env bash
# The exact commands from the article "How to read a .npy (NumPy) file with SQL".
# Run ./generate.sh first to create the sample arrays in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read a .npy array (the format must be named explicitly) =="
clickhouse local -q "SELECT * FROM file('revenue.npy', Npy) LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. See the dtype without declaring a schema =="
clickhouse local -q "DESCRIBE file('revenue.npy', Npy) FORMAT PrettyCompact"

echo
echo "== 3. Rename the column and aggregate =="
clickhouse local -q "
SELECT count() AS n, round(avg(array), 2) AS mean, round(max(array), 2) AS max
FROM file('revenue.npy', Npy)
FORMAT PrettyCompact"

echo
echo "== 4. Give the column a name with an explicit structure =="
clickhouse local -q "
SELECT revenue FROM file('revenue.npy', Npy, 'revenue Float64')
WHERE revenue > 130
ORDER BY revenue DESC
FORMAT PrettyCompact"

echo
echo "== 5. Zip two .npy arrays into rows by position =="
clickhouse local -q "
SELECT r.rn AS i, r.array AS revenue, q.array AS quantity
FROM (SELECT rowNumberInAllBlocks() AS rn, array FROM file('revenue.npy', Npy)) AS r
INNER JOIN (SELECT rowNumberInAllBlocks() AS rn, array FROM file('quantity.npy', Npy)) AS q
USING rn
ORDER BY i
FORMAT PrettyCompact"

echo
echo "== 6. Perf: aggregate the 3,000,000-value scores_large.npy (best-of-3, warm) =="
Q="SELECT count(), round(avg(array), 3), round(quantile(0.95)(array), 3) FROM file('scores_large.npy', Npy)"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_npy_time.txt
  echo "run $i: $(grep real /tmp/_npy_time.txt)"
done
clickhouse local -q "$Q FORMAT PrettyCompact"
