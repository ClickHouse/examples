#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <database_name> <table_name>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
TABLE_NAME="$2"
DUCKDB_CMD="duckdb $DATABASE_NAME"

# Fetch the total size using duckDB
$DUCKDB_CMD -c "select '$TABLE_NAME' as table_name, count(distinct block_id) as num_blocks, count(distinct block_id) * (select block_size from pragma_database_size()) as num_bytes from pragma_storage_info('$TABLE_NAME') group by all;"

