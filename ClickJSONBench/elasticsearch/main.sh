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
    local template=$2
    ./create_and_load.sh "bluesky-${template}-${size}m" "index_template_${template}" "$DATA_DIRECTORY" "$size" "$SUCCESS_LOG" "$ERROR_LOG"
    ./total_size.sh "bluesky-${template}-${size}m" | tee "${OUTPUT_PREFIX}_bluesky-${template}-${size}m.data_size"
    ./count.sh "bluesky-${template}-${size}m" | tee "${OUTPUT_PREFIX}_bluesky-${template}-${size}m.count"
    ./benchmark.sh "bluesky-${template}-${size}m" "${OUTPUT_PREFIX}_bluesky-${template}-${size}m.results_runtime"
}

case $choice in
    2)
        benchmark 10 no_source_best_compression
        benchmark 10 source_best_compression
        benchmark 10 source_default_compression
        benchmark 10 no_source_default_compression
        ;;
    3)
        benchmark 100 no_source_best_compression
        benchmark 100 source_best_compression
        benchmark 100 source_default_compression
        benchmark 100 no_source_default_compression
        ;;
    4)
        benchmark 1000 no_source_best_compression
        benchmark 1000 source_best_compression
        benchmark 1000 source_default_compression
        benchmark 1000 no_source_default_compression
        ;;
    5)
        benchmark 1 no_source_best_compression
        benchmark 1 source_best_compression
        benchmark 1 source_default_compression
        benchmark 1 no_source_default_compression
        benchmark 10 no_source_best_compression
        benchmark 10 source_best_compression
        benchmark 10 source_default_compression
        benchmark 10 no_source_default_compression
        benchmark 100 no_source_best_compression
        benchmark 100 source_best_compression
        benchmark 100 source_default_compression
        benchmark 100 no_source_default_compression
        benchmark 1000 no_source_best_compression
        benchmark 1000 source_best_compression
        benchmark 1000 source_default_compression
        benchmark 1000 no_source_default_compression
        ;;
    *)
        benchmark 1 no_source_best_compression
        benchmark 1 source_best_compression
        benchmark 1 source_default_compression
        benchmark 1 no_source_default_compression
        ;;
esac
