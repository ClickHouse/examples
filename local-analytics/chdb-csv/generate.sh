#!/usr/bin/env bash
# Generate the sample CSV files used by the read-csv-file-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data

# 1. Small CSV WITH a header row (CSVWithNames). Mixed types: int, string,
#    float, date — so type inference has something to show.
# Deterministic amount so the captured/embedded output is reproducible.
clickhouse local -q "
SELECT
  number AS order_id,
  ['GB','AU','IN','US'][(number % 4) + 1]              AS country,
  ['book','pen','mug','lamp'][(number % 4) + 1]        AS product,
  round((cityHash64(number,'a') % 10000) / 100.0, 2)   AS amount,
  toDate('2026-01-01') + (number % 28)                 AS order_date
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/orders.csv' TRUNCATE FORMAT CSVWithNames
"

# 2. A headerless CSV (plain CSV) — same rows, no header line. Used to show
#    how chDB names columns c1, c2, ... when there is no header to infer from.
clickhouse local -q "
SELECT
  number AS order_id,
  ['GB','AU','IN','US'][(number % 4) + 1]              AS country,
  ['book','pen','mug','lamp'][(number % 4) + 1]        AS product,
  round((cityHash64(number,'a') % 10000) / 100.0, 2)   AS amount,
  toDate('2026-01-01') + (number % 28)                 AS order_date
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/orders_noheader.csv' TRUNCATE FORMAT CSV
"

# 3. A larger CSV with a header (3M rows, ~110 MB) for the perf contrast.
clickhouse local -q "
SELECT
  number AS order_id,
  ['GB','AU','IN','US'][(cityHash64(number) % 4) + 1]   AS country,
  ['book','pen','mug','lamp'][(cityHash64(number,'p') % 4) + 1] AS product,
  round((cityHash64(number,'a') % 100000) / 100.0, 2)   AS amount,
  toDate('2026-01-01') + (cityHash64(number,'d') % 28)  AS order_date
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/orders_large.csv' TRUNCATE FORMAT CSVWithNames
"

echo "Generated:"
ls -lh data
