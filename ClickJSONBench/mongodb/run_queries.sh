#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

# Number of tries for each query
TRIES=3

# File containing MongoDB queries (replace 'queries.js' with your file)
QUERY_FILE="queries.js"

# Check if the query file exists
if [[ ! -f "$QUERY_FILE" ]]; then
    echo "Error: Query file '$QUERY_FILE' does not exist."
    exit 1
fi

# Read and execute each query
cat "$QUERY_FILE" | while read -r query; do

    # Stop MongoDB service
    echo "Stopping MongoDB service..."
    sudo systemctl stop mongod

    # Wait for MongoDB to stop
    echo "Waiting for 10 seconds for MongoDB service to stop..."
    sleep 10
    while systemctl is-active --quiet mongod; do
        sleep 1
    done
    echo "MongoDB service stopped."


    # Clear the Linux file system cache
    echo "Clearing file system cache..."
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    echo "File system cache cleared."

    # Start MongoDB service
    echo "Starting MongoDB service..."
    sudo systemctl start mongod

    # Wait for MongoDB to start
    echo "Waiting for 10 seconds for MongoDB service to start..."
    sleep 10
    while ! systemctl is-active --quiet mongod; do
        sleep 1
    done
    echo "MongoDB service is running."

    # Print the query
    echo "Running query: $query"

    # Escape the query for safe passing to mongosh
    ESCAPED_QUERY=$(echo "$query" | sed 's/\([\"\\]\)/\\\1/g' | sed 's/\$/\\$/g')

    # Execute the query multiple times
    for i in $(seq 1 $TRIES); do
        mongosh --quiet --eval "
            const db = db.getSiblingDB('$DB_NAME');
            const start = new Date();
            const result = eval(\"$ESCAPED_QUERY\");
            // Force query execution -> When using commands like aggregate() or find(),
            // the query is not fully executed until the data is actually fetched or processed.
            if (Array.isArray(result)) {
                result.length;  // Access the length to force evaluation for arrays
            } else if (typeof result === 'object' && typeof result.toArray === 'function') {
                result.toArray();  // Force execution for cursors
            }
            const end = new Date();
            print('Execution time: ' + (end.getTime() - start.getTime()) + 'ms');
        "
    done
done