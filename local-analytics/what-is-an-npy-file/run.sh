#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-an-npy-file
set -euo pipefail
cd "$(dirname "$0")"
SMALL="$(pwd)/data/readings.npy"
LARGE="$(pwd)/data/readings_large.npy"

if [[ ! -f "$SMALL" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. The .npy header: magic string + version + dtype/shape ==="
clickhouse local -q "
SELECT
    substring(file('$SMALL'), 1, 6)               AS magic,
    reinterpretAsUInt8(substring(file('$SMALL'), 7, 1)) AS version_major,
    reinterpretAsUInt8(substring(file('$SMALL'), 8, 1)) AS version_minor,
    trim(substring(file('$SMALL'), 11, 60))        AS header_dict
FROM numbers(1)
FORMAT Vertical"

echo
echo "=== 2. DESCRIBE infers the element type from the header dtype ==="
clickhouse local -q "DESCRIBE file('$SMALL', Npy)"

echo
echo "=== 3. Read the array back (one column called 'array') ==="
clickhouse local -q "
SELECT array AS reading
FROM file('$SMALL', Npy)
LIMIT 8
FORMAT Pretty"

echo
echo "=== 4. Run SQL over it (count/min/max/avg) ==="
clickhouse local -q "
SELECT count() AS n,
       min(array)        AS min_reading,
       max(array)        AS max_reading,
       round(avg(array), 3) AS avg_reading
FROM file('$SMALL', Npy)
FORMAT Vertical"

echo
echo "=== 5. Same SQL, larger array ($(printf "%'d" 3000000) rows) ==="
clickhouse local -q "
SELECT count() AS n,
       round(avg(array), 4) AS avg_reading
FROM file('$LARGE', Npy)
FORMAT Vertical"
