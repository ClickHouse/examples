#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <INDEX_NAME>"
    exit 1
fi

# Check if ELASTIC_PASSWORD env variable is set, if set from not read from .elastic_password file
if [[ -z "$ELASTIC_PASSWORD" ]]; then
    [[ ! -f ".elastic_password" ]] && { echo "Error: ELASTIC_PASSWORD environment variable is not set and .elastic_password file does not exist."; exit 1; }
    export $(cat .elastic_password)
fi

# Arguments
INDEX_NAME="$1"

QUERY_NUM=1

# File containing Elasticsearch ES|SQL queries
QUERY_FILE="queries.txt"

# Check if the query file exists
if [[ ! -f "$QUERY_FILE" ]]; then
    echo "Error: Query file '$QUERY_FILE' does not exist."
    exit 1
fi

cat 'queries.txt' | while read -r QUERY; do
    eval "QUERY=\"${QUERY}\""
    # Print the query
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Result for query Q$QUERY_NUM: "
    echo
    CURL_DATA="{\"query\": \"$QUERY\"}"
    curl -s -k -X POST "https://localhost:9200/_query?format=txt" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -d "$CURL_DATA"
    echo
     # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))
done
