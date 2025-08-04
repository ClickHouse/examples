#!/bin/bash

# Usage: ./run_queries.sh [bytes|KiB|MiB]
SIZE_UNIT="${1:-KiB}"  # Default to KiB if no argument is provided

# Map SIZE_UNIT to ls --block-size option
case "$SIZE_UNIT" in
    bytes) BLOCK_SIZE=1 ;;
    KiB) BLOCK_SIZE=1K ;;
    MiB) BLOCK_SIZE=1M ;;
    *)
        echo "Invalid size unit. Use: bytes, KiB, or MiB"
        exit 1
        ;;
esac

# Output directory for CSV files
OUTPUT_DIR="benchmark_csv"
mkdir -p "$OUTPUT_DIR"

# Database and connection options
CLICKHOUSE_CLIENT="clickhouse-client --database=default --format CSV"

# Queries
$CLICKHOUSE_CLIENT -q "
SELECT l_discount, l_tax, l_extendedprice, l_returnflag, l_linestatus, l_shipmode, l_comment
FROM lineitem_base_tbl_1part
WHERE l_commitdate = '1996-02-01' AND l_quantity = 1
" > "$OUTPUT_DIR/q1.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_discount, l_tax, l_extendedprice, l_returnflag, l_linestatus, l_comment
FROM lineitem_base_tbl_1part
WHERE l_commitdate = '1996-07-07' AND l_quantity = 2
" > "$OUTPUT_DIR/q2.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_extendedprice, l_returnflag, l_linestatus, l_tax
FROM lineitem_base_tbl_1part
WHERE l_orderkey % 1000000 = 123456
" > "$OUTPUT_DIR/q3.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_extendedprice, l_linestatus, l_shipmode, l_comment
FROM lineitem_base_tbl_1part
WHERE l_receiptdate = '1996-06-06' AND l_orderkey % 1000 = 777
" > "$OUTPUT_DIR/q4.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_comment, l_discount, l_tax
FROM lineitem_base_tbl_1part
WHERE l_orderkey = 100000000
" > "$OUTPUT_DIR/q5.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_shipinstruct, l_returnflag, l_comment
FROM lineitem_base_tbl_1part
WHERE l_shipdate = '1996-09-09' AND l_quantity = 4
" > "$OUTPUT_DIR/q6.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_extendedprice, l_tax, l_linestatus, l_comment
FROM lineitem_base_tbl_1part
WHERE l_commitdate = '1995-08-08' AND l_quantity = 5
" > "$OUTPUT_DIR/q7.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_returnflag, l_shipinstruct, l_comment
FROM lineitem_base_tbl_1part
WHERE l_orderkey < 500000 AND l_commitdate < '1995-01-01'
" > "$OUTPUT_DIR/q8.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_comment, l_discount
FROM lineitem_base_tbl_1part
WHERE l_suppkey BETWEEN 100 AND 110 AND l_quantity = 3
" > "$OUTPUT_DIR/q9.csv"

$CLICKHOUSE_CLIENT -q "
SELECT l_discount, l_tax, l_extendedprice, l_returnflag, l_linestatus, l_shipinstruct, l_comment
FROM lineitem_base_tbl_1part
WHERE l_receiptdate = '1997-01-15' AND l_quantity = 2
" > "$OUTPUT_DIR/q10.csv"

# --- List the output files with chosen unit ---
echo
echo "Generated CSV files in '$OUTPUT_DIR' (sizes in $SIZE_UNIT):"
ls -lh --block-size=$BLOCK_SIZE "$OUTPUT_DIR"/q*.csv | awk '{printf "%-20s %10s\n", $9, $5}'