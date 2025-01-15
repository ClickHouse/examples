#!/bin/bash

# Check if required arguments are provided
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <DATA_DIRECTORY> <TARGET_DIRECTORY> <N>"
    exit 1
fi

# Arguments
DATA_DIRECTORY="$1"
TARGET_DIRECTORY="$2"
N="$3"

# Validate the source directory
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

# Validate the target directory
if [[ ! -d "$TARGET_DIRECTORY" ]]; then
    echo "Error: Target directory '$TARGET_DIRECTORY' does not exist."
    exit 1
fi

# Validate N is a positive integer
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
    echo "Error: N must be a positive integer."
    exit 1
fi

# Get the sorted list of .json.gz files and extract the first N
count=0
for file in $(ls "$DATA_DIRECTORY"/*.json.gz | sort); do
    if [[ $count -ge $N ]]; then
        break
    fi

    echo "Processing $file..."
    gzip -dkc "$file" > "$TARGET_DIRECTORY/$(basename "${file%.gz}")"  # Extract to target directory
    count=$((count + 1))
done

echo "Extraction of $count files completed. Extracted files are in '$TARGET_DIRECTORY'."