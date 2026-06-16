#!/usr/bin/env bash
# Generate small demo .npy files locally with clickhouse local.
# An .npy file holds ONE numeric NumPy array. We write a 1-D array of
# sensor readings (Float64) and a larger one for a perf number.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

SMALL="$(pwd)/data/readings.npy"
LARGE="$(pwd)/data/readings_large.npy"
rm -f "$SMALL" "$LARGE"

# Small array: 20 Float64 "temperature" readings. One array, one column.
clickhouse local -q "
SELECT round(18 + 8 * sin(number / 3.0), 2) AS array
FROM numbers($SMALL_ROWS)
INTO OUTFILE '$SMALL'
FORMAT Npy
"

# Larger array for the perf note.
clickhouse local -q "
SELECT round(18 + 8 * sin(number / 1000.0), 4) AS array
FROM numbers($LARGE_ROWS)
INTO OUTFILE '$LARGE'
FORMAT Npy
"

ls -lh "$SMALL" "$LARGE"
