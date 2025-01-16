#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 7 ]]; then
    echo "Usage: $0 <INDEX_NAME> <INDEX_TEMPLATE_FILE> <DATA_DIRECTORY> <NUM_FILES> <SUCCESS_LOG> <ERROR_LOG>"
    exit 1
fi

# Arguments
INDEX_NAME="$1"
INDEX_TEMPLATE_FILE="config/$2"
DATA_DIRECTORY="$3"
NUM_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"

# Validate arguments
[[ ! -f "$INDEX_TEMPLATE_FILE" ]] && { echo "Error: Index template file '$INDEX_TEMPLATE_FILE' does not exist."; exit 1; }
[[ ! -d "$DATA_DIRECTORY" ]] && { echo "Error: Data directory '$DATA_DIRECTORY' does not exist."; exit 1; }
[[ ! "$NUM_FILES" =~ ^[0-9]+$ ]] && { echo "Error: NUM_FILES must be a positive integer."; exit 1; }

# Install index template
# Read index template file json from config/$INDEX_TEMPLATE_FILE 
INDEX_TEMPLATE=$(cat "$INDEX_TEMPLATE_FILE")
eval "INDEX_TEMPLATE=\"${INDEX_TEMPLATE}\""
echo $INDEX_TEMPLATE
# Load data
#./load_data.sh "$DATA_DIRECTORY" "$DB_NAME" "$COLLECTION_NAME" "$NUM_FILES" "$SUCCESS_LOG" "$ERROR_LOG"

echo "Script completed successfully."