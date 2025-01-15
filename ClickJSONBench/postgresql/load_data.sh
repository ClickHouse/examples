#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <directory> <database_name> <table_name> <max_files> <success_log> <error_log>"
    exit 1
fi

# Arguments
DIRECTORY="$1"
DB_NAME="$2"
TABLE_NAME="$3"
MAX_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"
PSQL_CMD="sudo -u postgres psql -d $DB_NAME"

# Validate that MAX_FILES is a number
if ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]]; then
    echo "Error: <max_files> must be a positive integer."
    exit 1
fi

# Ensure the log files exist
touch "$SUCCESS_LOG" "$ERROR_LOG"

# Create a temporary directory in /var/tmp and ensure it's accessible
TEMP_DIR=$(mktemp -d /var/tmp/cleaned_files.XXXXXX)
chmod 777 "$TEMP_DIR"  # Allow access for all users
trap "rm -rf $TEMP_DIR" EXIT  # Ensure cleanup on script exit

# Counter to track processed files
counter=0

# Loop through each .json.gz file in the directory
for file in $(ls "$DIRECTORY"/*.json.gz | sort); do
    if [[ -f "$file" ]]; then
        echo "Processing $file..."
        counter=$((counter + 1))

        # Uncompress the file into the temporary directory
        uncompressed_file="$TEMP_DIR/$(basename "${file%.gz}")"
        gunzip -c "$file" > "$uncompressed_file"

        # Check if uncompression was successful
        if [[ $? -ne 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to uncompress $file." >> "$ERROR_LOG"
            continue
        fi

        # Preprocess the file to remove null characters
        cleaned_file="$TEMP_DIR/$(basename "${uncompressed_file%.json}_cleaned.json")"
        sed 's/\\u0000//g' "$uncompressed_file" > "$cleaned_file"

        # Grant read permissions for the postgres user
        chmod 644 "$cleaned_file"

        # Import the cleaned JSON file into PostgreSQL
        $PSQL_CMD -c "\COPY $TABLE_NAME FROM '$cleaned_file' WITH (format csv, quote e'\x01', delimiter e'\x02', escape e'\x01');"
        import_status=$?

        # Check if the import was successful
        if [[ $import_status -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $cleaned_file into PostgreSQL." >> "$SUCCESS_LOG"
            # Delete both the uncompressed and cleaned files after successful processing
            rm -f "$uncompressed_file" "$cleaned_file"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to import $cleaned_file. See errors above." >> "$ERROR_LOG"
            # Keep the files for debugging purposes
        fi

        # Stop processing if the max number of files is reached
        if [[ $counter -ge $MAX_FILES ]]; then
            echo "Processed maximum number of files: $MAX_FILES"
            break
        fi
    else
        echo "No .json.gz files found in the directory."
    fi
done

echo "All files have been processed."