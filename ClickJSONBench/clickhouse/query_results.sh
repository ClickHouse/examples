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

    # Print the query
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Result for query Q$QUERY_NUM:"
    echo

    clickhouse-client --database="$DB_NAME" --format=PrettyCompactMonoBlock --query="$query" --progress 0

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))
done;