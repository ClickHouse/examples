#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

QUERY_NUM=1

# File containing MongoDB queries (replace 'queries.js' with your file)
QUERY_FILE="queries.js"

# Check if the query file exists
if [[ ! -f "$QUERY_FILE" ]]; then
    echo "Error: Query file '$QUERY_FILE' does not exist."
    exit 1
fi

cat "$QUERY_FILE" | while read -r query; do

    # Print the query number
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Index usage for query Q$QUERY_NUM:"
    echo

    # Modify the query to include the explain option inside the aggregate call
    MODIFIED_QUERY=$(echo "$query" | sed 's/]);$/], { explain: "queryPlanner" });/')

    # Escape the modified query for safe passing to mongosh
    ESCAPED_QUERY=$(echo "$MODIFIED_QUERY" | sed 's/\([\"\\]\)/\\\1/g' | sed 's/\$/\\$/g')

    mongosh --quiet --eval "
        const db = db.getSiblingDB('$DB_NAME');
        const result = eval(\"$ESCAPED_QUERY\");
        printjson(result.stages[0].\$cursor.queryPlanner.winningPlan);
    "

    # Increment the query number
    QUERY_NUM=$((QUERY_NUM + 1))
done;