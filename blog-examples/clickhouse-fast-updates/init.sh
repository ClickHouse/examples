#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"
DATA_URL="https://clickhouse-datasets.s3.amazonaws.com/h/100/lineitem.tbl.gz"

# Common table schema
TABLE_SCHEMA="(
    l_orderkey       Int32,
    l_partkey        Int32,
    l_suppkey        Int32,
    l_linenumber     Int32,
    l_quantity       Decimal(15,2),
    l_extendedprice  Decimal(15,2),
    l_discount       Decimal(15,2),
    l_tax            Decimal(15,2),
    l_returnflag     String,
    l_linestatus     String,
    l_shipdate       Date,
    l_commitdate     Date,
    l_receiptdate    Date,
    l_shipinstruct   String,
    l_shipmode       String,
    l_comment        String
) ENGINE = MergeTree
ORDER BY (l_orderkey, l_linenumber)
SETTINGS max_bytes_to_merge_at_max_space_in_pool = 1"  # ensure stable part count

# Function to create and populate a table
create_table() {
    local table_name="$1"
    local min_block_size_rows="$2"
    local expected_parts="$3"

    echo "Creating and populating table: $table_name ($expected_parts parts)..."

    $CLICKHOUSE_CLIENT --query "
        CREATE OR REPLACE TABLE $table_name $TABLE_SCHEMA;
    "

    $CLICKHOUSE_CLIENT --query "
        INSERT INTO $table_name
        SELECT *
        FROM s3('$DATA_URL', NOSIGN, CSV)
        SETTINGS
            format_csv_delimiter = '|',
            input_format_defaults_for_omitted_fields = 1,
            input_format_csv_empty_as_default = 1,
            max_insert_threads = 1,
            min_insert_block_size_bytes = 0,
            min_insert_block_size_rows = $min_block_size_rows;
    "

    echo "Verifying table $table_name:"
    $CLICKHOUSE_CLIENT --query "
        SELECT
            formatReadableQuantity(sum(rows))       AS rows,
            formatReadableQuantity(count())         AS parts,
            formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncomp,
            formatReadableSize(sum(data_compressed_bytes))   AS size_comp
        FROM system.parts
        WHERE active AND database = 'default' AND \`table\` = '$table_name';
    "
    echo
}

# Create the tables with 1, 2, and 20 parts
create_table "lineitem_base_tbl_1part"  600100000  1
create_table "lineitem_base_tbl_2part"  300100000  2
create_table "lineitem_base_tbl_20part"  30100000 20

echo "✅ All tables created and verified."