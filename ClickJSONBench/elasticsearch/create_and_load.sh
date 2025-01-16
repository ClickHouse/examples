#!/bin/bash

# Check if ELASTIC_PASSWORD env variable is set, if set from not read from .elastic_password file
if [[ -z "$ELASTIC_PASSWORD" ]]; then
    [[ ! -f ".elastic_password" ]] && { echo "Error: ELASTIC_PASSWORD environment variable is not set and .elastic_password file does not exist."; exit 1; }
    export $(cat .elastic_password)
fi

# Check if the required arguments are provided
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <INDEX_NAME> <INDEX_TEMPLATE_FILE> <DATA_DIRECTORY> <NUM_FILES> <SUCCESS_LOG> <ERROR_LOG>"
    exit 1
fi

# Arguments
INDEX_NAME="$1"
INDEX_TEMPLATE_FILE="config/$2.json"
DATA_DIRECTORY="$3"
NUM_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"

# Validate arguments
[[ ! -f "$INDEX_TEMPLATE_FILE" ]] && { echo "Error: Index template file '$INDEX_TEMPLATE_FILE' does not exist."; exit 1; }
[[ ! -d "$DATA_DIRECTORY" ]] && { echo "Error: Data directory '$DATA_DIRECTORY' does not exist."; exit 1; }
[[ ! "$NUM_FILES" =~ ^[0-9]+$ ]] && { echo "Error: NUM_FILES must be a positive integer."; exit 1; }

# Check ilm policy is installed, install if not
# If curl return 404, means ILM policy is not installed

http_code=$(curl -s -o /dev/null -k -w "%{http_code}" -X GET "https://localhost:9200/_ilm/policy/filebeat" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json')
if [[ "$http_code" -eq 404 ]] ; then
    echo "Installing ILM policy"
    ILM_POLICY=$(cat "config/ilm.json")
    curl -s -k -X PUT "https://localhost:9200/_ilm/policy/filebeat" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -d "$ILM_POLICY"
fi

# Install index template
# Read index template file json from config/$INDEX_TEMPLATE_FILE 
INDEX_TEMPLATE=$(cat "$INDEX_TEMPLATE_FILE")
JSON_DATA=$(cat $INDEX_TEMPLATE_FILE | sed "s/\${INDEX_NAME}/$INDEX_NAME/g")
echo "Install index template"
curl -s -o /dev/null -k -X PUT "https://localhost:9200/_index_template/${INDEX_NAME}" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -d "$JSON_DATA"

# Create the data stream
echo "Create the data stream"
curl -s -o /dev/null -k -X PUT "https://localhost:9200/_data_stream/${INDEX_NAME}" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json'

# Load data
./load_data.sh "$DATA_DIRECTORY" "$INDEX_NAME" "$NUM_FILES" "$SUCCESS_LOG" "$ERROR_LOG"

echo "Script completed successfully."