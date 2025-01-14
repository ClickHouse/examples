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

# Create a temporary directory inside the current directory
TEMP_DIR="./temp_extraction"
if [[ -d "$TEMP_DIR" ]]; then
    echo "Temporary directory '$TEMP_DIR' already exists. Deleting it first..."
    rm -rf "$TEMP_DIR"
fi

mkdir -p "$TEMP_DIR"

# Trap to ensure cleanup of the temporary directory
trap "rm -rf $TEMP_DIR" EXIT

# Process the first N files
count=0
for file in $(ls "$DATA_DIRECTORY"/*.json.gz | sort); do
    if [[ $count -ge $N ]]; then
        break
    fi

    echo "Processing $file..."

    # Define paths for the temporary extracted file and compressed file
    extracted_file="$TEMP_DIR/$(basename "${file%.gz}")"
    compressed_file="$TEMP_DIR/$(basename "${file%.gz}.zst")"

    # Extract the .json.gz file into the temporary directory
    gzip -c -d "$file" > "$extracted_file"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to extract $file to $extracted_file"
        continue
    fi

    # Compress the extracted file with zstd
    zstd -1 "$extracted_file" -o "$compressed_file"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to compress $extracted_file"
        continue
    fi

    # Copy the .zst file to the target directory
    cp "$compressed_file" "$TARGET_DIRECTORY/"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to copy $compressed_file to $TARGET_DIRECTORY"
        continue
    fi

    count=$((count + 1))
done

# Cleanup (done automatically by the trap)
echo "Processed $count files. Compressed files are in '$TARGET_DIRECTORY'."
echo "Temporary directory '$TEMP_DIR' has been deleted."