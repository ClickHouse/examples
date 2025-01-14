#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 7 ]]; then
    echo "Usage: $0 <DB_NAME> <TABLE_NAME> <DDL_FILE> <DATA_DIRECTORY> <NUM_FILES> <SUCCESS_LOG> <ERROR_LOG>"
    exit 1
fi

# Arguments
DB_NAME="$1"
TABLE_NAME="$2"
DDL_FILE="$3"
DATA_DIRECTORY="$4"
NUM_FILES="$5"
SUCCESS_LOG="$6"
ERROR_LOG="$7"

# Validate arguments
[[ ! -f "$DDL_FILE" ]] && { echo "Error: DDL file '$DDL_FILE' does not exist."; exit 1; }
[[ ! -d "$DATA_DIRECTORY" ]] && { echo "Error: Data directory '$DATA_DIRECTORY' does not exist."; exit 1; }
[[ ! "$NUM_FILES" =~ ^[0-9]+$ ]] && { echo "Error: NUM_FILES must be a positive integer."; exit 1; }

# Create database and execute DDL
duckdb $DB_NAME < "$DDL_FILE"

# Load data
./load_data.sh "$DATA_DIRECTORY" "$DB_NAME" "$TABLE_NAME" "$NUM_FILES" "$SUCCESS_LOG" "$ERROR_LOG"

echo "Script completed successfully."