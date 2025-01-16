#!/bin/bash

# Default data directory
DEFAULT_DATA_DIRECTORY=~/data/bluesky

# Allow the user to optionally provide the data directory as an argument
DATA_DIRECTORY="${1:-$DEFAULT_DATA_DIRECTORY}"

# Define prefix for output files
OUTPUT_PREFIX="${2:-_files_gz}"

# Check if the data directory exists
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi


# 1m
./total_size.sh "$DATA_DIRECTORY" 1 | tee "${OUTPUT_PREFIX}_1m.total_size"

# 10m
./total_size.sh "$DATA_DIRECTORY" 10 | tee "${OUTPUT_PREFIX}_10m.total_size"

# 100m
./total_size.sh "$DATA_DIRECTORY" 100 | tee "${OUTPUT_PREFIX}_100m.total_size"

# 1000m
./total_size.sh "$DATA_DIRECTORY" 1000 | tee "${OUTPUT_PREFIX}_1000m.total_size"