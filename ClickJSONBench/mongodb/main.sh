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

# bluesky_1m_snappy
./create_and_load.sh bluesky_1m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_snappy.total_size"
./data_size.sh bluesky_1m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_snappy.data_size"
./index_size.sh bluesky_1m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_snappy.index_size"
./index_usage.sh bluesky_1m_snappy | tee "${OUTPUT_PREFIX}_bluesky_1m_snappy.index_usage"
./query_results.sh bluesky_1m_snappy | tee "${OUTPUT_PREFIX}_bluesky_1m_snappy.query_results"
./benchmark.sh bluesky_1m_snappy "${OUTPUT_PREFIX}_bluesky_1m_snappy.results_runtime"

# bluesky_1m_zstd
./create_and_load.sh bluesky_1m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.total_size"
./data_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.data_size"
./index_size.sh bluesky_1m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.index_size"
./index_usage.sh bluesky_1m_zstd | tee "${OUTPUT_PREFIX}_bluesky_1m_zstd.index_usage"
./benchmark.sh bluesky_1m_zstd "${OUTPUT_PREFIX}_bluesky_1m_zstd.results_runtime"

# bluesky_10m_snappy
./create_and_load.sh bluesky_10m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_10m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_snappy.total_size"
./data_size.sh bluesky_10m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_snappy.data_size"
./index_size.sh bluesky_10m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_snappy.index_size"
./index_usage.sh bluesky_10m_snappy | tee "${OUTPUT_PREFIX}_bluesky_10m_snappy.index_usage"
./benchmark.sh bluesky_10m_snappy "${OUTPUT_PREFIX}_bluesky_10m_snappy.results_runtime"

# bluesky_10m_zstd
./create_and_load.sh bluesky_10m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.total_size"
./data_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.data_size"
./index_size.sh bluesky_10m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.index_size"
./index_usage.sh bluesky_10m_zstd | tee "${OUTPUT_PREFIX}_bluesky_10m_zstd.index_usage"
./benchmark.sh bluesky_10m_zstd "${OUTPUT_PREFIX}_bluesky_10m_zstd.results_runtime"

# bluesky_100m_snappy
./create_and_load.sh bluesky_100m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_100m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_snappy.total_size"
./data_size.sh bluesky_100m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_snappy.data_size"
./index_size.sh bluesky_100m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_snappy.index_size"
./index_usage.sh bluesky_100m_snappy | tee "${OUTPUT_PREFIX}_bluesky_100m_snappy.index_usage"
./benchmark.sh bluesky_100m_snappy "${OUTPUT_PREFIX}_bluesky_100m_snappy.results_runtime"

# bluesky_100m_zstd
./create_and_load.sh bluesky_100m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.total_size"
./data_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.data_size"
./index_size.sh bluesky_100m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.index_size"
./index_usage.sh bluesky_100m_zstd | tee "${OUTPUT_PREFIX}_bluesky_100m_zstd.index_usage"
./benchmark.sh bluesky_100m_zstd "${OUTPUT_PREFIX}_bluesky_100m_zstd.results_runtime"

# bluesky_1000m_snappy
./create_and_load.sh bluesky_1000m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1000m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_snappy.total_size"
./data_size.sh bluesky_1000m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_snappy.data_size"
./index_size.sh bluesky_1000m_snappy bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_snappy.index_size"
./index_usage.sh bluesky_1000m_snappy | tee "${OUTPUT_PREFIX}_bluesky_1000m_snappy.index_usage"
./benchmark.sh bluesky_1000m_snappy "${OUTPUT_PREFIX}_bluesky_1000m_snappy.results_runtime"

# bluesky_1000m_zstd
./create_and_load.sh bluesky_1000m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
./total_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.total_size"
./data_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.data_size"
./index_size.sh bluesky_1000m_zstd bluesky | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.index_size"
./index_usage.sh bluesky_1000m_zstd | tee "${OUTPUT_PREFIX}_bluesky_1000m_zstd.index_usage"
./benchmark.sh bluesky_1000m_zstd "${OUTPUT_PREFIX}_bluesky_1000m_zstd.results_runtime"