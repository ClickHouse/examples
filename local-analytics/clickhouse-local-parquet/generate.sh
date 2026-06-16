#!/usr/bin/env bash
# Generate the sample Parquet files used by the article, using clickhouse local
# itself so nothing large is committed to git. Idempotent: re-running overwrites.
set -euo pipefail
cd "$(dirname "$0")"
DATA_DIR="${1:-data}"
mkdir -p "$DATA_DIR"

DEMO_ROWS=${DEMO_ROWS:-100000}
LARGE_ROWS=${LARGE_ROWS:-70000000}   # ~1 GB Parquet, for the perf number

# Deterministic event data: every value is a hash of the row number, so the
# same row count produces the exact same file on every machine and every run.
gen_query() {
  local rows=$1
  cat <<SQL
SELECT
  toDateTime('2026-01-01 00:00:00') + toIntervalSecond(cityHash64(number, 1) % 15552000) AS event_time,
  (cityHash64(number, 2) % 1000000)::UInt32 AS user_id,
  ['US','GB','DE','FR','IN','BR','JP','CA','AU','NL'][(cityHash64(number, 3) % 10) + 1] AS country,
  ['mobile','desktop','tablet'][(cityHash64(number, 4) % 3) + 1] AS device,
  ['view','click','add_to_cart','purchase','refund'][(cityHash64(number, 5) % 5) + 1] AS event_type,
  round((cityHash64(number, 6) % 50000) / 100.0, 2) AS revenue,
  (cityHash64(number, 7) % 5 + 1)::UInt8 AS quantity
FROM numbers($rows)
SQL
}

echo "Generating data.parquet ($DEMO_ROWS rows)..."
clickhouse local -q "$(gen_query "$DEMO_ROWS") INTO OUTFILE '$DATA_DIR/data.parquet' TRUNCATE FORMAT Parquet"

echo "Generating data.zstd.parquet (zstd-compressed)..."
clickhouse local -q "SELECT * FROM file('$DATA_DIR/data.parquet') INTO OUTFILE '$DATA_DIR/data.zstd.parquet' TRUNCATE FORMAT Parquet SETTINGS output_format_parquet_compression_method='zstd'"

echo "Generating events_large.parquet ($LARGE_ROWS rows, ~1 GB)..."
clickhouse local -q "$(gen_query "$LARGE_ROWS") INTO OUTFILE '$DATA_DIR/events_large.parquet' TRUNCATE FORMAT Parquet"

echo
echo "Generated files:"
ls -lh "$DATA_DIR"/*.parquet
