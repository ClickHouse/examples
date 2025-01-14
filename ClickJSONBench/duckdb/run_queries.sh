#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

DUCKDB_CMD="duckdb $DB_NAME"

TRIES=3

cat queries.sql | while read -r query; do
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

    echo "Running query: $query"
    for i in $(seq 1 $TRIES); do
        # Correct here-document usage
        REAL_TIME=$($DUCKDB_CMD <<EOF | grep -oP 'real\s+\K[\d.]+'
            .timer on
            $query
            EOF
            )
        echo "$REAL_TIME"
    done
done