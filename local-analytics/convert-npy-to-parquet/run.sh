#!/usr/bin/env bash
# The exact commands from the article "How to convert NPY to Parquet".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert NPY -> Parquet in one line =="
clickhouse local -q "SELECT * FROM file('readings.npy') INTO OUTFILE 'readings.parquet' TRUNCATE FORMAT Parquet"
echo "wrote readings.parquet"

echo
echo "== 2. The NPY column is always named 'array' =="
clickhouse local -q "DESCRIBE file('readings.npy')"

echo
echo "== 3. Rename it to something meaningful during the conversion =="
clickhouse local -q "SELECT array AS reading FROM file('readings.npy') INTO OUTFILE 'readings.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "DESCRIBE file('readings.parquet')"
clickhouse local -q "SELECT * FROM file('readings.parquet')"

echo
echo "== 4. A 2D NPY (a matrix) becomes one Array column per row =="
clickhouse local -q "DESCRIBE file('embeddings.npy')"

echo
echo "== 5. Convert the matrix, keeping the row vectors as an Array column =="
clickhouse local -q "SELECT array AS embedding FROM file('embeddings.npy') INTO OUTFILE 'embeddings.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "DESCRIBE file('embeddings.parquet')"
clickhouse local -q "SELECT count() AS rows, length(any(embedding)) AS dims FROM file('embeddings.parquet')"

echo
echo "== 6. Or expand each vector into named scalar columns =="
clickhouse local -q "
SELECT array[1] AS f0, array[2] AS f1, array[3] AS f2
FROM file('embeddings.npy')
INTO OUTFILE 'embeddings_flat.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "DESCRIBE file('embeddings_flat.parquet')"
clickhouse local -q "SELECT * FROM file('embeddings_flat.parquet') LIMIT 3"

echo
echo "== 7. File size: NPY (uncompressed) vs Parquet (compressed) =="
ls -la embeddings.npy embeddings.parquet | awk '{print $5, $9}'

echo
echo "== 8. Perf: convert the 2,000,000 x 16 embeddings.npy -> Parquet (best-of-3, warm) =="
Q="SELECT array AS embedding FROM file('embeddings.npy') INTO OUTFILE 'embeddings.parquet' TRUNCATE FORMAT Parquet"
clickhouse local -q "$Q"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" 2> /tmp/_npy_time.txt
  echo "run $i: $(grep real /tmp/_npy_time.txt)"
done
