#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <database_name> <collection_name>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
COLLECTION_NAME="$2"

# Fetch the totalSize using mongosh
total_size=$(mongosh --quiet --eval "
    const db = db.getSiblingDB('$DATABASE_NAME');
    const stats = db.getCollection('$COLLECTION_NAME').stats();
    print(stats.totalIndexSize);
")

# Print the result
if [[ -z "$total_size" ]]; then
    echo "Error: Unable to fetch totalSize. Ensure the database and collection exist."
    exit 1
else
    echo $total_size
fi