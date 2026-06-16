#!/usr/bin/env bash
# Generate the sample .npy files locally with clickhouse local, so nothing large
# is committed to git. Writes into ./data/ (gitignored):
#   data/revenue.npy   - SMALL_ROWS Float64 values (the worked example array)
#   data/quantity.npy  - SMALL_ROWS Int32 values  (a second array, same length)
#   data/scores_large.npy - LARGE_ROWS Float64 values (the perf number)
# An .npy file holds exactly ONE numeric array, so each "column" is its own file.
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-10}
LARGE_ROWS=${LARGE_ROWS:-3000000}

echo "Generating data/revenue.npy ($SMALL_ROWS Float64 values)..."
clickhouse local -q "
SELECT round(100 + (number * 7) % 53 + number / 10.0, 2)::Float64 AS array
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/revenue.npy' TRUNCATE FORMAT Npy
"

echo "Generating data/quantity.npy ($SMALL_ROWS Int32 values)..."
clickhouse local -q "
SELECT ((number * 3) % 5 + 1)::Int32 AS array
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/quantity.npy' TRUNCATE FORMAT Npy
"

echo "Generating data/scores_large.npy ($LARGE_ROWS Float64 values)..."
clickhouse local -q "
SELECT (rand(1) % 1000000 / 1000.0)::Float64 AS array
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/scores_large.npy' TRUNCATE FORMAT Npy
"

echo
echo "Generated files:"
ls -la data
