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
DUCKDB_CMD="duckdb $DB_NAME"

# Validate that MAX_FILES is a number
if ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]]; then
    echo "Error: <max_files> must be a positive integer."
    exit 1
fi

# Ensure the log files exist
touch "$SUCCESS_LOG" "$ERROR_LOG"

counter=0

# Loop through each .json.gz file in the directory
for file in $(ls "$DIRECTORY"/*.json.gz | sort); do
    # if [[ -f "$file" ]]; then
    #     $DUCKDB_CMD -c "insert into $TABLE_NAME select * from read_ndjson_objects('$file', ignore_errors=false, maximum_object_size=1048576000);"
    # fi
    if [[ -f "$file" ]]; then
        # Create a temporary directory for split files
        temp_dir=$(mktemp -d $DIRECTORY/temp.XXXXXX)
        
        # Decompress and split the file into smaller chunks of 100000 lines each
        gzip -dc "$file" | split -l 100000 - "$temp_dir/chunk_"
        
        # Insert each chunk into DuckDB
        for chunk in "$temp_dir"/chunk_*; do
            $DUCKDB_CMD -c "insert into $TABLE_NAME select * from read_ndjson_objects('$chunk', ignore_errors=false, maximum_object_size=1048576000);"
        done
        
        # Clean up temporary directory
        rm -r "$temp_dir"
        counter=$((counter + 1))
    fi
    
    # Stop processing if the max number of files is reached
    if [[ $counter -ge $MAX_FILES ]]; then
        echo "Copied maximum number of files: $MAX_FILES"
        break
    fi
done

echo "All files have been imported."