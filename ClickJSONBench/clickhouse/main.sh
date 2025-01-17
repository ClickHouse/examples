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

# bluesky_1m_lz4
./create_and_load.sh bluesky_1m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_lz4.total_size"
./data_size.sh bluesky_1m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_lz4.data_size"
./index_size.sh bluesky_1m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_lz4.index_size"
./index_usage.sh bluesky_1m_lz4 | tee "${OUTPUT_PREFIX}_bluesky_1m_lz4.index_usage"
./benchmark.sh bluesky_1m_lz4 "${OUTPUT_PREFIX}_bluesky_1m_lz4.results_runtime" "${OUTPUT_PREFIX}_bluesky_1m_lz4.results_memory_usage"

# bluesky_1m_zstd
./create_and_load.sh bluesky_1m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.total_size"
./data_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.data_size"
./index_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.index_size"
./index_usage.sh bluesky_1m_zstd | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.index_usage"
./benchmark.sh bluesky_1m_zstd "${OUTPUT_PREFIX}_bluesky_1m_zstd.results_runtime" "${OUTPUT_PREFIX}_bluesky_1m_zstd.results_memory_usage"

# bluesky_10m_lz4
./create_and_load.sh bluesky_10m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_10m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_lz4.total_size"
./data_size.sh bluesky_10m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_lz4.data_size"
./index_size.sh bluesky_10m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_lz4.index_size"
./index_usage.sh bluesky_10m_lz4 | tee "${OUTPUT_PREFIX}_bluesky_10m_lz4.index_usage"
./benchmark.sh bluesky_10m_lz4 "${OUTPUT_PREFIX}_bluesky_10m_lz4.results_runtime" "${OUTPUT_PREFIX}_bluesky_10m_lz4.results_memory_usage"

# bluesky_10m_zstd
./create_and_load.sh bluesky_10m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.total_size"
./data_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.data_size"
./index_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.index_size"
./index_usage.sh bluesky_10m_zstd | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.index_usage"
./benchmark.sh bluesky_10m_zstd "${OUTPUT_PREFIX}_bluesky_10m_zstd.results_runtime" "${OUTPUT_PREFIX}_bluesky_10m_zstd.results_memory_usage"

# bluesky_100m_lz4
./create_and_load.sh bluesky_100m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_100m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_lz4.total_size"
./data_size.sh bluesky_100m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_lz4.data_size"
./index_size.sh bluesky_100m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_lz4.index_size"
./index_usage.sh bluesky_100m_lz4 | tee "${OUTPUT_PREFIX}_bluesky_100m_lz4.index_usage"
./benchmark.sh bluesky_100m_lz4 "${OUTPUT_PREFIX}_bluesky_100m_lz4.results_runtime" "${OUTPUT_PREFIX}_bluesky_100m_lz4.results_memory_usage"

# bluesky_100m_zstd
./create_and_load.sh bluesky_100m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.total_size"
./data_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.data_size"
./index_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.index_size"
./index_usage.sh bluesky_100m_zstd | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.index_usage"
./benchmark.sh bluesky_100m_zstd "${OUTPUT_PREFIX}_bluesky_100m_zstd.results_runtime" "${OUTPUT_PREFIX}_bluesky_100m_zstd.results_memory_usage"

# bluesky_1000m_lz4
./create_and_load.sh bluesky_1000m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1000m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_lz4.total_size"
./data_size.sh bluesky_1000m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_lz4.data_size"
./index_size.sh bluesky_1000m_lz4 bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_lz4.index_size"
./index_usage.sh bluesky_1000m_lz4 | tee "${OUTPUT_PREFIX}_bluesky_1000m_lz4.index_usage"
./benchmark.sh bluesky_1000m_lz4 "${OUTPUT_PREFIX}_bluesky_1000m_lz4.results_runtime" "${OUTPUT_PREFIX}_bluesky_1000m_lz4.results_memory_usage"

# bluesky_1000m_zstd
./create_and_load.sh bluesky_1000m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.total_size"
./data_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.data_size"
./index_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.index_size"
./index_usage.sh bluesky_1000m_zstd | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.index_usage"
./benchmark.sh bluesky_1000m_zstd "${OUTPUT_PREFIX}_bluesky_1000m_zstd.results_runtime" "${OUTPUT_PREFIX}_bluesky_1000m_zstd.results_memory_usage"