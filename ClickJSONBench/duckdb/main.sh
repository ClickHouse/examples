#!/bin/bash

# Default data directory
DEFAULT_DATA_DIRECTORY=~/data/bluesky

# Allow the user to optionally provide the data directory as an argument
DATA_DIRECTORY="${1:-$DEFAULT_DATA_DIRECTORY}"

# Define success and error log files
SUCCESS_LOG="${2:-success.log}"
ERROR_LOG="${3:-error.log}"

# Define prefix for output files
OUTPUT_PREFIX="${4:-_m6i.8xlarge}"

# Check if the directory exists
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

./install.sh

# bluesky_1m
./create_and_load.sh db.duckdb_1 bluesky ddl.sql "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh db.duckdb_1 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m.data_size"
./benchmark.sh db.duckdb_1 "${OUTPUT_PREFIX}_bluesky_1m.results_runtime"

# bluesky_10m
./create_and_load.sh db.duckdb_10 bluesky ddl.sql "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh db.duckdb_10 bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m.data_size"
./benchmark.sh db.duckdb_10 "${OUTPUT_PREFIX}_bluesky_10m.results_runtime"

# bluesky_100m
./create_and_load.sh db.duckdb_100 bluesky ddl.sql "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh db.duckdb_100 bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m.data_size"
./benchmark.sh db.duckdb_100 "${OUTPUT_PREFIX}_bluesky_100m.results_runtime"

# bluesky_1000m
./create_and_load.sh db.duckdb_1000 bluesky ddl.sql "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh db.duckdb_1000 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m.data_size"
./benchmark.sh db.duckdb_1000 "${OUTPUT_PREFIX}_bluesky_1000m.results_runtime"