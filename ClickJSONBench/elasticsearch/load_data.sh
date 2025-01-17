#!/bin/bash 

# Check if the required arguments are provided
if [[ $# -lt 5 ]]; then
    echo "Usage: $0 <directory> <index_name> <max_files> <success_log> <error_log>"
    exit 1
fi

# Check if ELASTIC_PASSWORD env variable is set, if set from not read from .elastic_password file
if [[ -z "$ELASTIC_PASSWORD" ]]; then
    [[ ! -f ".elastic_password" ]] && { echo "Error: ELASTIC_PASSWORD environment variable is not set and .elastic_password file does not exist."; exit 1; }
    export $(cat .elastic_password)
fi

# Arguments
DIRECTORY="$1"
INDEX_NAME="$2"
MAX_FILES="$3"
SUCCESS_LOG="$4"
ERROR_LOG="$5"

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

# Copy all files to temp location and uncompress them
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

        # Grant read permissions for the postgres user
        chmod 644 "$uncompressed_file"
        # Stop processing if the max number of files is reached
        if [[ $counter -ge $MAX_FILES ]]; then
            echo "Processed maximum number of files: $MAX_FILES"
            break
        fi
    else
        echo "No .json.gz files found in the directory."
    fi
done

echo "All files have been copied to temp location."

echo "Prepare filebeat for ingestion"

# Prepare Filebeat configuration
FILEBEAT_API_KEY=$(cat .filebeat_api_key)
FILEBEAT_CONFIG=$(sed -e "s|<api_key>|$FILEBEAT_API_KEY|g" -e "s|<index_name>|$INDEX_NAME|g" -e "s|<temp_dir>|"${TEMP_DIR}/*"|g" config/filebeat.yml)
echo "$FILEBEAT_CONFIG" | sudo tee /etc/filebeat/filebeat.yml > /dev/null

sudo service filebeat start
trap "sudo service filebeat stop" EXIT  # Stop filebeat on exit

# wait until all files have been ingested 
total_processed=0
max_events=$MAX_FILES*1000000
while [[ $total_processed -lt $max_events ]]; do
    sleep 30
    total_processed=$(curl -k -s -XGET 'localhost:5066/stats' | jq .filebeat.events.done)
    echo "Total processed files: $total_processed"
done

echo "Force merge indices"
curl -k -X POST "https://localhost:9200/$INDEX_NAME/_forcemerge?max_num_segments=1" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json'

sudo service filebeat stop

echo "All files have been processed."