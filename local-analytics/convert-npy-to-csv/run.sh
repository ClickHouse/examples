#!/usr/bin/env bash
# The exact commands from the article "How to convert NPY to CSV".
# Run ./generate.sh first to create the sample .npy files in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert a 1D .npy to .csv in one line =="
clickhouse local -q "SELECT * FROM file('signal.npy') INTO OUTFILE 'signal.csv' TRUNCATE FORMAT CSVWithNames"
cat signal.csv

echo
echo "== 2. Inspect the inferred type (Npy carries dtype, no schema needed) =="
clickhouse local -q "DESCRIBE file('signal.npy')"

echo
echo "== 3. A 2D .npy reads as one Array column =="
clickhouse local -q "DESCRIBE file('matrix.npy')"
clickhouse local -q "SELECT * FROM file('matrix.npy')"

echo
echo "== 4. Naive convert of the 2D array: quoted list per row (probably NOT what you want) =="
clickhouse local -q "SELECT * FROM file('matrix.npy') INTO OUTFILE 'matrix_naive.csv' TRUNCATE FORMAT CSV"
cat matrix_naive.csv

echo
echo "== 5. Expand the array into real CSV columns =="
clickhouse local -q "
SELECT array[1] AS c0, array[2] AS c1, array[3] AS c2
FROM file('matrix.npy')
INTO OUTFILE 'matrix.csv' TRUNCATE FORMAT CSVWithNames
"
cat matrix.csv

echo
echo "== 6. Perf: convert the 3,000,000-element signal_large.npy to CSV (best-of-3, warm) =="
clickhouse local -q "SELECT array AS value FROM file('signal_large.npy') INTO OUTFILE 'signal_large.csv' TRUNCATE FORMAT CSVWithNames" > /dev/null  # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT array AS value FROM file('signal_large.npy') INTO OUTFILE 'signal_large.csv' TRUNCATE FORMAT CSVWithNames" 2> /tmp/_npy_time.txt
  echo "run $i: $(grep real /tmp/_npy_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('signal_large.csv')"
echo "output size:"
ls -la signal_large.csv | awk '{print $5, $9}'
