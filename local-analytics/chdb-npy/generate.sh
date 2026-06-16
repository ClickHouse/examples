#!/usr/bin/env bash
# Generate the sample .npy files used by the read-npy-file-python how-to.
# Numeric arrays are written locally with `clickhouse local` (Npy format) so
# nothing large is committed to git. Idempotent: re-running overwrites them.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data

# 1. A small 1-D Float64 array of sensor readings (for the worked examples).
clickhouse local -q "
SELECT round(50 + 40 * sin(number / 3.0), 2)::Float64 AS reading
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/readings.npy' TRUNCATE FORMAT Npy
"

# 2. A second 1-D array of the SAME length: a quality flag per reading (0/1).
#    Two separate .npy files is the normal NumPy shape -- one array per file.
clickhouse local -q "
SELECT (number % 4 != 0)::UInt8 AS ok
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/flags.npy' TRUNCATE FORMAT Npy
"

# 3. A small 2-D Int64 array (rows of fixed-width vectors) written with NumPy,
#    to show ClickHouse reads it as an Array(Int64) column.
python3 - <<'PY'
import numpy as np
np.save("data/matrix.npy", np.arange(12, dtype="int64").reshape(4, 3))
PY

# 4. A larger 1-D Float64 array + a paired flag array, both LARGE_ROWS long,
#    for the honest perf contrast vs NumPy (a masked mean across two files).
clickhouse local -q "
SELECT round(randUniform(0, 1000), 4)::Float64 AS v
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/large.npy' TRUNCATE FORMAT Npy
"
clickhouse local -q "
SELECT (cityHash64(number) % 4 != 0)::UInt8 AS ok
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/large_flags.npy' TRUNCATE FORMAT Npy
"

echo "Generated:"
ls -lh data
