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
    local compression=$2
    ./create_and_load.sh "bluesky_${size}m_${compression}" bluesky "ddl_${compression}.sql" "$DATA_DIRECTORY" "$size" "$SUCCESS_LOG" "$ERROR_LOG"
    ./total_size.sh "bluesky_${size}m_${compression}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.total_size"
    ./data_size.sh "bluesky_${size}m_${compression}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.data_size"
    ./index_size.sh "bluesky_${size}m_${compression}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.index_size"
    ./count.sh "bluesky_${size}m_${compression}" bluesky | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.count"

    ./index_usage.sh "bluesky_${size}m_${compression}" | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.index_usage"
    #./query_results.sh "bluesky_${size}m_${compression}" | tee "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.query_results"
    ./benchmark.sh "bluesky_${size}m_${compression}" "${OUTPUT_PREFIX}_bluesky_${size}m_${compression}.results_runtime"
}

case $choice in
    2)
        benchmark 10 lz4
        benchmark 10 pglz
        ;;
    3)
        benchmark 100 lz4
        benchmark 100 pglz
        ;;
    4)
        benchmark 1000 lz4
        benchmark 1000 pglz
        ;;
    5)
        benchmark 1 lz4
        benchmark 1 pglz
        benchmark 10 lz4
        benchmark 10 pglz
        benchmark 100 lz4
        benchmark 100 pglz
        benchmark 1000 lz4
        benchmark 1000 pglz
        ;;
    *)
        benchmark 1 lz4
        benchmark 1 pglz
        ;;
esac