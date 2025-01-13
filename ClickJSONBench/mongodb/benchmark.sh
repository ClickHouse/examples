#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

./run_queries.sh $DB_NAME 2>&1 | tee query_log.txt

cat query_log.txt | grep -oP 'Execution time: \d+ms' | sed -r 's/Execution time: ([0-9]+)/\1/' | \
awk '{ if (i % 3 == 0) { printf "[" }; printf $1 / 1000; if (i % 3 != 2) { printf "," } else { print "]," }; ++i; }'