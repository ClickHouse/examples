#!/bin/bash

# Default data directory
DEFAULT_DATA_DIRECTORY=~/data/bluesky
DEFAULT_TARGET_DIRECTORY=~/data/bluesky_zstd

# Allow the user to optionally provide the data and target directories as arguments
DATA_DIRECTORY="${1:-$DEFAULT_DATA_DIRECTORY}"
TARGET_DIRECTORY="${2:-$DEFAULT_TARGET_DIRECTORY}"

# Define prefix for output files
OUTPUT_PREFIX="${3:-_files_zstd}"

# Check if the data directory exists
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

# Ensure the target directory exists
if [[ ! -d "$TARGET_DIRECTORY" ]]; then
    echo "Target directory '$TARGET_DIRECTORY' does not exist. Creating it..."
    mkdir -p "$TARGET_DIRECTORY"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create target directory '$TARGET_DIRECTORY'."
        exit 1
    fi
fi


# 1m
TARGET_SUB_DIRECTORY="$TARGET_DIRECTORY/1m"
echo "Creating subdirectory: $TARGET_SUB_DIRECTORY"
mkdir -p "$TARGET_SUB_DIRECTORY"
./load_data.sh "$DATA_DIRECTORY" "$TARGET_SUB_DIRECTORY" 1
./data_size.sh "$TARGET_SUB_DIRECTORY" | tee "${OUTPUT_PREFIX}_1m_size"

# 10m
TARGET_SUB_DIRECTORY="$TARGET_DIRECTORY/10m"
echo "Creating subdirectory: $TARGET_SUB_DIRECTORY"
mkdir -p "$TARGET_SUB_DIRECTORY"
./load_data.sh "$DATA_DIRECTORY" "$TARGET_SUB_DIRECTORY" 10
./data_size.sh "$TARGET_SUB_DIRECTORY" | tee "${OUTPUT_PREFIX}_10m_size"

# 100m
TARGET_SUB_DIRECTORY="$TARGET_DIRECTORY/100m"
echo "Creating subdirectory: $TARGET_SUB_DIRECTORY"
mkdir -p "$TARGET_SUB_DIRECTORY"
./load_data.sh "$DATA_DIRECTORY" "$TARGET_SUB_DIRECTORY" 100
./data_size.sh "$TARGET_SUB_DIRECTORY" | tee "${OUTPUT_PREFIX}_100m_size"

# 1000m
TARGET_SUB_DIRECTORY="$TARGET_DIRECTORY/1000m"
echo "Creating subdirectory: $TARGET_SUB_DIRECTORY"
mkdir -p "$TARGET_SUB_DIRECTORY"
./load_data.sh "$DATA_DIRECTORY" "$TARGET_SUB_DIRECTORY" 1000
./data_size.sh "$TARGET_SUB_DIRECTORY" | tee "${OUTPUT_PREFIX}_1000m_size"