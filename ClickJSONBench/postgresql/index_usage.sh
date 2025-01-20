#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

QUERY_NUM=1


cat queries.sql | while read -r query; do

    # Print the query number
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Index usage for query Q$QUERY_NUM:"
    echo

    sudo -u postgres psql -d "$DB_NAME" -t -c "EXPLAIN $query"

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))

done;