#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

DUCKDB_CMD="duckdb $DB_NAME"

QUERY_NUM=1

cat queries.sql | while read -r query; do

    # Print the query
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Result for query Q$QUERY_NUM:"
    echo
    $DUCKDB_CMD <<EOF
$query
EOF
)

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))
done;