#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <directory> <database_name> <collection_name> <max_files> <success_log> <error_log>"
    exit 1
fi

# Arguments
DIRECTORY="$1"
DB_NAME="$2"
COLLECTION_NAME="$3"
MAX_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"
MONGO_URI="mongodb://localhost:27017"   # Replace with your MongoDB URI if necessary

# Validate that MAX_FILES is a number
if ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]]; then
    echo "Error: <max_files> must be a positive integer."
    exit 1
fi

# Ensure the log files exist
touch "$SUCCESS_LOG" "$ERROR_LOG"

# Create a temporary directory for uncompressed files
TEMP_DIR=$(mktemp -d /var/tmp/json_files.XXXXXX)
trap "rm -rf $TEMP_DIR" EXIT  # Ensure cleanup on script exit

# Counter to track processed files
counter=0

# Loop through each .json.gz file in the directory
for file in $(ls "$DIRECTORY"/*.json.gz 2>/dev/null | sort); do
    if [[ -f "$file" ]]; then
        echo "Processing $file..."
        counter=$((counter + 1))

        # Uncompress the file into the TEMP_DIR
        uncompressed_file="$TEMP_DIR/$(basename "${file%.gz}")"
        gunzip -c "$file" > "$uncompressed_file"

        # Check if uncompression was successful
        if [[ $? -ne 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to uncompress $file." >> "$ERROR_LOG"
            continue
        fi

        # Import the uncompressed JSON file into MongoDB
        mongoimport --uri "$MONGO_URI" --db "$DB_NAME" --collection "$COLLECTION_NAME" --file "$uncompressed_file"
        import_status=$?

        # Check if the import was successful
        if [[ $import_status -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $uncompressed_file into MongoDB." >> "$SUCCESS_LOG"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to import $uncompressed_file into MongoDB." >> "$ERROR_LOG"
        fi

        # Remove the uncompressed file after processing
        rm -f "$uncompressed_file"

        # Stop processing if the max number of files is reached
        if [[ $counter -ge $MAX_FILES ]]; then
            echo "Processed maximum number of files: $MAX_FILES"
            break
        fi
    fi
done

if [[ $counter -eq 0 ]]; then
    echo "No .json.gz files found in the directory."
fi

echo "All files have been processed."