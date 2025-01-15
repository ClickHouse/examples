#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <DATA_DIRECTORY> <DB_NAME> <TABLE_NAME> <MAX_FILES> <SUCCESS_LOG> <ERROR_LOG>"
    exit 1
fi


# Arguments
DATA_DIRECTORY="$1"
DB_NAME="$2"
TABLE_NAME="$3"
MAX_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"

# Validate arguments
[[ ! -d "$DATA_DIRECTORY" ]] && { echo "Error: Data directory '$DATA_DIRECTORY' does not exist."; exit 1; }
[[ ! "$MAX_FILES" =~ ^[0-9]+$ ]] && { echo "Error: MAX_FILES must be a positive integer."; exit 1; }


# Create a temporary directory for uncompressed files
TEMP_DIR=$(mktemp -d /var/tmp/json_files.XXXXXX)
trap "rm -rf $TEMP_DIR" EXIT  # Cleanup temp directory on script exit

# Load data
counter=0
for file in $(ls "$DATA_DIRECTORY"/*.json.gz | head -n "$MAX_FILES"); do
    echo "Processing file: $file"

    # Uncompress the file into the TEMP_DIR
    uncompressed_file="$TEMP_DIR/$(basename "${file%.gz}")"
    gunzip -c "$file" > "$uncompressed_file"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to uncompress $file" >> "$ERROR_LOG"
        continue
    fi

    # Attempt the first import
    clickhouse-client --query="INSERT INTO $DB_NAME.$TABLE_NAME SETTINGS min_insert_block_size_rows = 1_000_000, min_insert_block_size_bytes = 0 FORMAT JSONAsObject" < "$uncompressed_file"
    first_attempt=$?

    # Check if the first import was successful
    if [[ $first_attempt -eq 0 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $file." >> "$SUCCESS_LOG"
        rm -f "$uncompressed_file"  # Delete the uncompressed file after successful processing
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] First attempt failed for $file. Trying again..." >> "$ERROR_LOG"

        echo "Processing $file... again..."
        # Attempt the second import with a different command
        clickhouse-client --query="INSERT INTO $DB_NAME.$TABLE_NAME SETTINGS min_insert_block_size_rows = 1_000_000, min_insert_block_size_bytes = 0, input_format_allow_errors_num = 1_000_000_000, input_format_allow_errors_ratio=1 FORMAT JSONAsObject" < "$uncompressed_file"
        second_attempt=$?

        # Check if the second import was successful
        if [[ $second_attempt -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $file on second attempt." >> "$SUCCESS_LOG"
            rm -f "$uncompressed_file"  # Delete the uncompressed file after successful processing
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Both attempts failed for $file. Giving up." >> "$ERROR_LOG"
        fi
    fi

    counter=$((counter + 1))
    if [[ $counter -ge $MAX_FILES ]]; then
        break
    fi
done

echo "Script completed successfully."