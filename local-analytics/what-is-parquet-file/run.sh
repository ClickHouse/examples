#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/what-is-parquet-file
set -euo pipefail
cd "$(dirname "$0")"
FILE="$(pwd)/data/events.parquet"

if [[ ! -f "$FILE" ]]; then
  echo "Generating demo data first..."
  ./generate.sh
fi

echo "=== 1. Read the Parquet file (filter + aggregate) ==="
clickhouse local -q "
SELECT country, count() AS purchases, round(sum(revenue)) AS revenue
FROM file('$FILE')
WHERE event_type = 'purchase'
GROUP BY country
ORDER BY revenue DESC
FORMAT Pretty"

echo
echo "=== 2. Top-level Parquet metadata (no column data read) ==="
clickhouse local -q "
SELECT num_columns, num_rows, num_row_groups, format_version,
       formatReadableSize(total_uncompressed_size) AS uncompressed,
       formatReadableSize(total_compressed_size)   AS compressed
FROM file('$FILE', ParquetMetadata)
FORMAT Vertical"

echo
echo "=== 3. Per-column physical type, compression + ratio ==="
clickhouse local -q "
SELECT
    c.name AS column,
    c.5    AS physical_type,
    c.7    AS compression,
    c.10   AS compression_ratio
FROM file('$FILE', ParquetMetadata)
ARRAY JOIN columns AS c
FORMAT Pretty"

echo
echo "=== 4. Per-row-group min/max statistics for event_time (predicate pushdown) ==="
clickhouse local -q "
SELECT
    rg.num_rows AS rows,
    fromUnixTimestamp64Milli(toInt64(c.statistics.min)) AS event_time_min,
    fromUnixTimestamp64Milli(toInt64(c.statistics.max)) AS event_time_max
FROM file('$FILE', ParquetMetadata)
ARRAY JOIN row_groups AS rg
ARRAY JOIN arrayFilter(x -> x.name = 'event_time', rg.columns) AS c
FORMAT Pretty"
