#!/usr/bin/env bash
set -euo pipefail

# Usage: ./export_point_queries.sh [output_dir] [bytes|KiB|MiB]
OUTPUT_DIR="${1:-point_queries}"
SIZE_UNIT="${2:-KiB}" # default to KiB

# Configure size display
case "$SIZE_UNIT" in
    bytes) BLOCK_SIZE=1 ;;
    KiB) BLOCK_SIZE=1K ;;
    MiB) BLOCK_SIZE=1M ;;
    *)
        echo "Invalid size unit. Use: bytes, KiB, or MiB"
        exit 1
        ;;
esac

# Prepare output directory
mkdir -p "$OUTPUT_DIR"

# ClickHouse connection
CLICKHOUSE_CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client --database=default --format CSV}"

# Define queries: each line -> "columns|orderkey|linenumber"
QUERIES=(
    "l_discount,l_tax,l_extendedprice,l_returnflag,l_linestatus,l_shipmode,l_comment|503437255|3"
    "l_discount,l_tax,l_extendedprice,l_returnflag,l_linestatus,l_comment|522639521|3"
    "l_extendedprice,l_returnflag,l_linestatus,l_tax|431195557|3"
    "l_extendedprice,l_linestatus,l_shipmode,l_comment|198133573|5"
    "l_comment,l_discount,l_tax|93311302|2"
    "l_shipinstruct,l_returnflag,l_comment|343206944|1"
    "l_extendedprice,l_tax,l_linestatus,l_comment|140916002|5"
    "l_returnflag,l_shipinstruct,l_comment|349980483|1"
    "l_comment,l_discount|596681795|6"
    "l_discount,l_tax,l_extendedprice,l_returnflag,l_linestatus,l_shipinstruct,l_comment|400574597|7"
)

echo "Exporting ${#QUERIES[@]} point queries to $OUTPUT_DIR..."

# Loop through queries
for i in "${!QUERIES[@]}"; do
    idx=$((i+1))
    IFS='|' read -r columns orderkey linenumber <<< "${QUERIES[i]}"

    OUTPUT_FILE="$OUTPUT_DIR/q${idx}.csv"
    echo "Running Query $idx -> $OUTPUT_FILE"

    $CLICKHOUSE_CLIENT -q "
        SELECT $columns
        FROM lineitem_base_tbl
        WHERE l_orderkey = $orderkey AND l_linenumber = $linenumber
    " > "$OUTPUT_FILE"
done

# List file sizes
echo
echo "Generated CSV files (sizes in $SIZE_UNIT):"
ls -lh --block-size=$BLOCK_SIZE "$OUTPUT_DIR"/*.csv | awk '{print $9 ": " $5}'