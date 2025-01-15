#!/bin/bash

# Check if the required argument is provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DIRECTORY>"
    exit 1
fi

# Argument
DIRECTORY="$1"

# Check if the directory exists
if [[ ! -d "$DIRECTORY" ]]; then
    echo "Error: Directory '$DIRECTORY' does not exist."
    exit 1
fi

# Get the total size in bytes and suppress the directory name
du -sb "$DIRECTORY" | awk '{print $1}'