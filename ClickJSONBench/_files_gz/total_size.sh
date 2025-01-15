#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DATA_DIRECTORY> <N>"
    exit 1
fi

# Arguments
DATA_DIRECTORY="$1"
N="$2"

# Validate the data directory
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

# Validate N is a positive integer
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
    echo "Error: N must be a positive integer."
    exit 1
fi

# Get the first N files sorted by filename and calculate their total size
TOTAL_SIZE=$(ls -1 "$DATA_DIRECTORY" | sort | head -n "$N" | while read -r file; do
    filepath="$DATA_DIRECTORY/$file"
    if [[ -f "$filepath" ]]; then
        stat --format="%s" "$filepath"
    fi
done | awk '{sum += $1} END {print sum}')

# Output the total size in bytes
echo $TOTAL_SIZE