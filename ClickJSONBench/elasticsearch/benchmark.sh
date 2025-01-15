#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <INDEX_NAME> [RESULT_FILE]"
    exit 1
fi

# Arguments
INDEX_NAME="$1"
RESULT_FILE="${2:-}"

# Print the index name
echo "Running queries on index: $INDEX_NAME"

# Run queries and log the output
./run_queries.sh "$INDEX_NAME" 2>&1 | tee query_log.txt

# Process the query log and prepare the result
RESULT=$(cat query_log.txt | grep -oP 'Response time: \d+\.\d+ s' | sed -r -e 's/Response time: ([0-9]+\.[0-9]+) s/\1/' | \
awk '{ if (i % 3 == 0) { printf "[" }; printf $1; if (i % 3 != 2) { printf "," } else { print "]," }; ++i; }')

# Output the result
if [[ -n "$RESULT_FILE" ]]; then
    echo "$RESULT" > "$RESULT_FILE"
    echo "Result written to $RESULT_FILE"
else
    echo "$RESULT"
fi