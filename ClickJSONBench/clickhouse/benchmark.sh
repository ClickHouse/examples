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

# Construct the query log file name using $DB_NAME
QUERY_LOG_FILE="_query_log_${DB_NAME}.txt"

# Print the database name
echo "Running queries on database: $DB_NAME"

# Run queries and log the output
./run_queries.sh "$DB_NAME" 2>&1 | tee "$QUERY_LOG_FILE"

# Process the query log and prepare the result
RUNTIME_RESULTS=$(grep -E '^[0-9]' "$QUERY_LOG_FILE" | awk 'NR % 2 == 1' | awk '{
    if (NR % 3 == 1) { printf "["; }
    printf $1;
    if (NR % 3 == 0) {
        print "],";
    } else {
        printf ", ";
    }
}')

MEMORY_RESULTS=$(grep -E '^[0-9]' "$QUERY_LOG_FILE" | awk 'NR % 2 == 0' | awk '{
    if (NR % 3 == 1) { printf "["; }
    printf $1;
    if (NR % 3 == 0) {
        print "],";
    } else {
        printf ", ";
    }
}')

# Output the runtime results
echo "$RUNTIME_RESULTS" > "$RESULT_FILE_RUNTIMES"
echo "Runtime results written to $RESULT_FILE_RUNTIMES"

# Output the memory usage results
echo "$MEMORY_RESULTS" > "$RESULT_FILE_MEMORY_USAGE"
echo "Memory usage results written to $RESULT_FILE_MEMORY_USAGE"