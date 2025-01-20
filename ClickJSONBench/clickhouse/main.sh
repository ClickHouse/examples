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

echo "Select the dataset size to benchmark:"
echo "1) 1m (default)"
echo "2) 10m"
echo "3) 100m"
echo "4) 1000m"
echo "5) all"
read -p "Enter the number corresponding to your choice: " choice

./install.sh

benchmark() {
    local size=$1
    local suffix=$2
    ./create_and_load.sh "bluesky_${size}_${suffix}" bluesky "ddl_${suffix}.sql" "$DATA_DIRECTORY" "$size" "$SUCCESS_LOG" "$ERROR_LOG"
    ./total_size.sh "bluesky_${size}_${suffix}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.total_size"
    ./data_size.sh "bluesky_${size}_${suffix}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.data_size"
    ./index_size.sh "bluesky_${size}_${suffix}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.index_size"
    ./index_usage.sh "bluesky_${size}_${suffix}" | tee "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.index_usage"
    ./physical_query_plans.sh "bluesky_${size}_${suffix}" | tee "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.physical_query_plans"
    ./benchmark.sh "bluesky_${size}_${suffix}" "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.results_runtime" "${OUTPUT_PREFIX}_bluesky_${size}_${suffix}.results_memory_usage"
}

case $choice in
    2)
        benchmark 10m lz4
        benchmark 10m zstd
        ;;
    3)
        benchmark 100m lz4
        benchmark 100m zstd
        ;;
    4)
        benchmark 1000m lz4
        benchmark 1000m zstd
        ;;
    5)
        benchmark 1m lz4
        benchmark 1m zstd
        benchmark 10m lz4
        benchmark 10m zstd
        benchmark 100m lz4
        benchmark 100m zstd
        benchmark 1000m lz4
        benchmark 1000m zstd
        ;;
    *)
        benchmark 1m lz4
        benchmark 1m zstd
        ;;
esac