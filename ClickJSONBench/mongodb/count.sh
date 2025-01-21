#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <database_name> <collection_name>"
    exit 1
fi

# Arguments
DATABASE_NAME="$1"
COLLECTION_NAME="$2"

# Fetch the document count using mongosh
document_count=$(mongosh --quiet --eval "
    const db = db.getSiblingDB('$DATABASE_NAME');
    const count = db.getCollection('$COLLECTION_NAME').countDocuments();
    print(count);
")

# Debugging information
echo "Database: $DATABASE_NAME"
echo "Collection: $COLLECTION_NAME"
echo "Document count: $document_count"

# Print the result
if [[ -z "$document_count" ]]; then
    echo "Error: Unable to fetch document count. Ensure the database and collection exist."
    exit 1
else
    echo $document_count
fi