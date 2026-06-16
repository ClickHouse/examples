#!/usr/bin/env bash
# Generate sample .npy files locally with clickhouse local, so nothing large is
# committed to git. Writes into ./data/ (gitignored):
#   data/readings.npy    - SMALL_ROWS 1D float values (scalar per row, the worked example)
#   data/embeddings.npy  - LARGE_ROWS x DIM 2D float32 matrix (the perf number)
# A .npy holds ONE numeric array, so each file is a single column named `array`.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-10}
LARGE_ROWS=${LARGE_ROWS:-2000000}
DIM=${DIM:-16}

echo "Generating data/readings.npy ($SMALL_ROWS 1D float values)..."
clickhouse local -q "
SELECT round(20 + sin(number / 2.0) * 5, 4)::Float64 AS reading
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/readings.npy' TRUNCATE FORMAT Npy
"

echo "Generating data/embeddings.npy ($LARGE_ROWS x $DIM float32 matrix)..."
clickhouse local -q "
SELECT arrayMap(i -> (sipHash64(number, i) % 2000 - 1000) / 1000.0, range($DIM))::Array(Float32) AS embedding
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/embeddings.npy' TRUNCATE FORMAT Npy
"

echo
echo "Generated files:"
ls -la data
