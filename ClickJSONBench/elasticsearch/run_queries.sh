#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <INDEX_NAME>"
    exit 1
fi

# Arguments
INDEX_NAME="$1"

# Number of tries for each query
TRIES=3

# File containing Elasticsearch ES|SQL queries
QUERY_FILE="queries.txt"

# Check if the query file exists
if [[ ! -f "$QUERY_FILE" ]]; then
    echo "Error: Query file '$QUERY_FILE' does not exist."
    exit 1
fi

cat 'queries.txt' | while read -r QUERY; do
    # Clear filesystem cache between queries.
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    # Clear query cache between queries.
    curl -k -X POST 'https://localhost:9200/hits/_cache/clear?pretty' -u "elastic:${ELASTIC_PASSWORD}" &>/dev/null
    eval "QUERY=\"${QUERY}\""
    echo "Running query: $QUERY"
    for i in $(seq 1 $TRIES); do
        CURL_DATA="{\"query\": \"$QUERY\"}"
        curl -s -k -X POST "https://localhost:9200/_query" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -w '\n* Response time: %{time_total} s\n' -d "$CURL_DATA"
    done
done
