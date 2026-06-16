#!/usr/bin/env bash
# Generate the sample .npy files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/signal.npy   - 1D Float64 array (the worked example)
#   data/matrix.npy   - 2D Int32 array, 3 columns wide (the array-column gotcha)
#   data/signal_large.npy - LARGE_ROWS 1D Float64 array (the perf number)
# Npy holds ONE numeric array per file; these are written with FORMAT Npy.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-10}
MATRIX_ROWS=${MATRIX_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/signal.npy ($SMALL_ROWS-element 1D Float64 array)..."
clickhouse local -q "
SELECT round(sin(number / 2.0) * 100, 4)::Float64 AS array
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/signal.npy' TRUNCATE FORMAT Npy
"

echo "Generating data/matrix.npy ($MATRIX_ROWS x 3 Int32 2D array)..."
clickhouse local -q "
SELECT [number * 3, number * 3 + 1, number * 3 + 2]::Array(Int32) AS array
FROM numbers($MATRIX_ROWS)
INTO OUTFILE 'data/matrix.npy' TRUNCATE FORMAT Npy
"

echo "Generating data/signal_large.npy ($LARGE_ROWS-element 1D Float64 array)..."
clickhouse local -q "
SELECT (rand(1) % 1000000) / 1000.0 AS array
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/signal_large.npy' TRUNCATE FORMAT Npy
"

echo
echo "Generated files:"
ls -la data
