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

    # Stop ClickHouse service
    echo "Stopping ClickHouse service..."
    sudo clickhouse stop

    # Clear the Linux file system cache
    echo "Clearing file system cache..."
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    echo "File system cache cleared."

    # Start ClickHouse service
    echo "Starting ClickHouse service..."
    sudo clickhouse start

    while true
    do
        clickhouse-client --format=Null --query "SELECT 1" && break
        sleep 1
    done
    echo "ClickHouse service started."


    echo "$query";
    for i in $(seq 1 $TRIES); do
        clickhouse-client --database="$DB_NAME" --time --memory-usage --format=Null --query="$query" --progress 0
    done;
done;