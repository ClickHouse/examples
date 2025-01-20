#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <index_name>"
    exit 1
fi

# Check if ELASTIC_PASSWORD env variable is set, if set from not read from .elastic_password file
if [[ -z "$ELASTIC_PASSWORD" ]]; then
    [[ ! -f ".elastic_password" ]] && { echo "Error: ELASTIC_PASSWORD environment variable is not set and .elastic_password file does not exist."; exit 1; }
    export $(cat .elastic_password)
fi

# Arguments
INDEX_NAME="$1"

# Get data size
curl -k -XGET "https://localhost:9200/_data_stream/${INDEX_NAME}/_stats?human" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json'