#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

TRIES=3

cat queries.sql | while read -r query; do
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

    echo "$query";
    for i in $(seq 1 $TRIES); do
        clickhouse-client --database="$DB_NAME" --time --memory-usage --format=Null --query="$query" --progress 0
    done;
done;