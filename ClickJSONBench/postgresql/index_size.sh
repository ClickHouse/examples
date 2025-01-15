#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"
TABLE_NAME="$2"

sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT pg_relation_size(oid) FROM pg_class WHERE relname = 'idx_bluesky'"