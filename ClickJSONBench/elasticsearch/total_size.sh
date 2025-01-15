#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <index_name>"
    exit 1
fi

# Arguments
INDEX_NAME="$1"

# Get data size
curl -k -XGET "https://localhost:9200/_data_stream/${INDEX_NAME}/_stats?human" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json'