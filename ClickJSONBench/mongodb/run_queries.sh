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

# Set the internalQueryMaxAddToSetBytes parameter to 1 GB
echo "Setting internalQueryMaxAddToSetBytes to 1 GB..."
mongosh --quiet --eval "
    const result = db.adminCommand({ setParameter: 1, internalQueryMaxAddToSetBytes: 1073741824 });
    if (result.ok !== 1) {
        print('Failed to set internalQueryMaxAddToSetBytes: ' + JSON.stringify(result));
        quit(1);
    } else {
        print('Successfully set internalQueryMaxAddToSetBytes to 1 GB');
    }
"

# Set the internalQueryPlannerGenerateCoveredWholeIndexScans parameter to true
echo "Setting internalQueryPlannerGenerateCoveredWholeIndexScans to true..."
mongosh --quiet --eval "
    const result = db.adminCommand({ setParameter: 1, internalQueryPlannerGenerateCoveredWholeIndexScans: true });
    if (result.ok !== 1) {
        print('Failed to set internalQueryPlannerGenerateCoveredWholeIndexScans: ' + JSON.stringify(result));
        quit(1);
    } else {
        print('Successfully set internalQueryPlannerGenerateCoveredWholeIndexScans to true');
    }
"

# Read and execute each query
cat "$QUERY_FILE" | while read -r query; do

    # Clear the Linux file system cache
    echo "Clearing file system cache..."
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    echo "File system cache cleared."

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