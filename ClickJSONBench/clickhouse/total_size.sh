#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DB_NAME> <TABLE_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"
TABLE_NAME="$2"

clickhouse-client --query "SELECT total_bytes FROM system.tables WHERE database = '$DB_NAME' AND name = '$TABLE_NAME'"