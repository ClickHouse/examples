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
LOG_FILE="query_log_$INDEX_NAME.log"
> "$LOG_FILE"

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
        RESPONSE=$(curl -s -k -X POST "https://localhost:9200/_query" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -d "$CURL_DATA")
        TOOK_MS=$(echo "$RESPONSE" | jq -r '.took' 2>/dev/null)
        
        # Convert 'took' to seconds (from ms to s)
        TOOK_S=$(bc <<< "scale=3; $TOOK_MS / 1000")
        TOOK_FORMATTED=$(printf "%.3f" "$TOOK_S")
        # TOOK_S=$(bc <<< "scale=3; ")
        echo "$RESPONSE" >> "$LOG_FILE"
        echo "Response time: ${TOOK_FORMATTED} s"
    done
done
