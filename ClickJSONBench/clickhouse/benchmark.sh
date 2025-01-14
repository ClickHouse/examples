#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <DB_NAME> <RESULT_FILE_RUNTIMES> <RESULT_FILE_MEMORY_USAGE>"
    exit 1
fi

# Arguments
DB_NAME="$1"
RESULT_FILE_RUNTIMES="$2"
RESULT_FILE_MEMORY_USAGE="$3"

# Print the database name
echo "Running queries on database: $DB_NAME"

# Run queries and log the output
./run_queries.sh "$DB_NAME" 2>&1 | tee query_log.txt

# Process the query log and prepare the result
RUNTIME_RESULTS=$(grep -v '^SELECT' query_log.txt | awk 'NR % 2 == 1' | grep -oP '^\d+(\.\d+)?' | \
awk '{ if (i % 3 == 0) { printf "[" }; printf $1; if (i % 3 != 2) { printf ", " } else { print "]," }; ++i; }')

MEMORY_RESULTS=$(grep -v '^SELECT' query_log.txt | awk 'NR % 2 == 0' | grep -oP '^\d+(\.\d+)?' | \
awk '{ if (i % 3 == 0) { printf "[" }; printf $1; if (i % 3 != 2) { printf ", " } else { print "]," }; ++i; }')

# Output the runtime results
echo "$RUNTIME_RESULTS" > "$RESULT_FILE_RUNTIMES"
echo "Runtime results written to $RESULT_FILE_RUNTIMES"

# Output the memory usage results
echo "$MEMORY_RESULTS" > "$RESULT_FILE_MEMORY_USAGE"
echo "Memory usage results written to $RESULT_FILE_MEMORY_USAGE"