#!/usr/bin/env bash
set -euo pipefail

# Usage: ./column_sizes.sh [database] [table]
DB_NAME="${1:-default}"
TABLE_NAME="${2:-lineitem_base_tbl_1part}"
CLICKHOUSE_CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

echo "Checking compressed and uncompressed column sizes for $DB_NAME.$TABLE_NAME..."

$CLICKHOUSE_CLIENT --database="$DB_NAME" --query "
SELECT
    query,
    formatReadableSize(data_compressed_bytes) AS compressed,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed
FROM
(
    SELECT 1 AS query, sum(data_compressed_bytes) AS data_compressed_bytes, sum(data_uncompressed_bytes) AS data_uncompressed_bytes
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_discount','l_tax','l_extendedprice','l_returnflag','l_linestatus','l_shipmode','l_comment')

    UNION ALL
    SELECT 2, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_discount','l_tax','l_extendedprice','l_returnflag','l_linestatus','l_comment')

    UNION ALL
    SELECT 3, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_extendedprice','l_returnflag','l_linestatus','l_tax')

    UNION ALL
    SELECT 4, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_extendedprice','l_linestatus','l_shipmode','l_comment')

    UNION ALL
    SELECT 5, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_comment','l_discount','l_tax')

    UNION ALL
    SELECT 6, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_shipinstruct','l_returnflag','l_comment')

    UNION ALL
    SELECT 7, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_extendedprice','l_tax','l_linestatus','l_comment')

    UNION ALL
    SELECT 8, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_returnflag','l_shipinstruct','l_comment')

    UNION ALL
    SELECT 9, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_comment','l_discount')

    UNION ALL
    SELECT 10, sum(data_compressed_bytes), sum(data_uncompressed_bytes)
    FROM system.columns
    WHERE database = '$DB_NAME' AND table = '$TABLE_NAME'
      AND name IN ('l_discount','l_tax','l_extendedprice','l_returnflag','l_linestatus','l_shipinstruct','l_comment')
) ORDER BY query;
"

echo
echo "✅ Column size summary generated."