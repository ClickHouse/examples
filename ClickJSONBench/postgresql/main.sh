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

chmod +x ./*.sh

./install.sh

# bluesky_1m_lz4
./create_and_load.sh bluesky_1m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_1m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_lz4.data_size"
./benchmark.sh bluesky_1m_lz4 "${OUTPUT_PREFIX}_bluesky_1m_lz4.result"

# bluesky_10m_lz4
./create_and_load.sh bluesky_10m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_10m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_lz4.data_size"
./benchmark.sh bluesky_10m_lz4 "${OUTPUT_PREFIX}_bluesky_10m_lz4.result"

# bluesky_100m_lz4
./create_and_load.sh bluesky_100m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_100m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_lz4.data_size"
./benchmark.sh bluesky_100m_lz4 "${OUTPUT_PREFIX}_bluesky_100m_lz4.result"

# bluesky_1000m_lz4
./create_and_load.sh bluesky_1000m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_1000m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_lz4.data_size"
./benchmark.sh bluesky_1000m_lz4 "${OUTPUT_PREFIX}_bluesky_1000m_lz4.result"

# bluesky_1m_pglz
./create_and_load.sh bluesky_1m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_1m_pglz bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_pglz.data_size"
./benchmark.sh bluesky_1m_pglz "${OUTPUT_PREFIX}_bluesky_1m_pglz.result"

# bluesky_10m_pglz
./create_and_load.sh bluesky_10m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_10m_pglz bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_pglz.data_size"
./benchmark.sh bluesky_10m_pglz "${OUTPUT_PREFIX}_bluesky_10m_pglz.result"

# bluesky_100m_pglz
./create_and_load.sh bluesky_100m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_100m_pglz bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_pglz.data_size"
./benchmark.sh bluesky_100m_pglz "${OUTPUT_PREFIX}_bluesky_100m_pglz.result"

# bluesky_1000m_pglz
./create_and_load.sh bluesky_1000m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./data_size.sh bluesky_1000m_pglz bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_pglz.data_size"
./benchmark.sh bluesky_1000m_pglz "${OUTPUT_PREFIX}_bluesky_1000m_pglz.result"