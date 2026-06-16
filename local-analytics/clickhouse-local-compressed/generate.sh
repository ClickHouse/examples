#!/usr/bin/env bash
# Generate sample compressed files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/events.csv.gz          - small gzipped CSV (the worked example)
#   data/events.csv.zst         - same data, zstd-compressed CSV
#   data/events.parquet         - uncompressed-codec Parquet (snappy default off)
#   data/events.zstd.parquet    - Parquet with zstd column compression
#   data/events_large.csv.gz    - large gzipped CSV (~modest, the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# The shared synthetic-event expression, reused for every file.
# Values derive deterministically from `number` (via cityHash64), so the data
# is byte-for-byte reproducible across runs and machines. No rand().
gen() { # $1 = row count
  cat <<SQL
SELECT
  toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 1) % 31536000)          AS event_time,
  number + 1                                                                      AS user_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(cityHash64(number, 2) % 10) + 1] AS country,
  ['desktop','mobile','tablet'][(cityHash64(number, 3) % 3) + 1]                  AS device,
  ['click','view','purchase','refund'][(cityHash64(number, 4) % 4) + 1]          AS event_type,
  round((cityHash64(number, 5) % 50000) / 100.0, 2)                              AS revenue,
  (cityHash64(number, 6) % 5 + 1)::UInt8                                          AS quantity
FROM numbers($1)
SQL
}

echo "Generating data/events.csv.gz ($SMALL_ROWS rows)..."
clickhouse local -q "$(gen "$SMALL_ROWS") INTO OUTFILE 'data/events.csv.gz' TRUNCATE FORMAT CSVWithNames"

echo "Generating data/events.csv.zst ($SMALL_ROWS rows)..."
clickhouse local -q "SELECT * FROM file('data/events.csv.gz') INTO OUTFILE 'data/events.csv.zst' TRUNCATE FORMAT CSVWithNames"

echo "Generating data/events.parquet (default codec)..."
clickhouse local -q "SELECT * FROM file('data/events.csv.gz') INTO OUTFILE 'data/events.parquet' TRUNCATE FORMAT Parquet"

echo "Generating data/events.zstd.parquet (zstd column compression)..."
clickhouse local -q "
SELECT * FROM file('data/events.csv.gz')
INTO OUTFILE 'data/events.zstd.parquet' TRUNCATE FORMAT Parquet
SETTINGS output_format_parquet_compression_method = 'zstd'"

echo "Generating data/events_large.csv.gz ($LARGE_ROWS rows)..."
clickhouse local -q "$(gen "$LARGE_ROWS") INTO OUTFILE 'data/events_large.csv.gz' TRUNCATE FORMAT CSVWithNames"

echo
echo "Generated files:"
ls -la data
