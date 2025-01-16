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

# ./install.sh

# bluesky-source-1m-best-compression
# ./create_and_load.sh bluesky-source-1m-best-compression index_template_source_best_compression "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-source-1m-best-compression.data_size"
# ./benchmark.sh bluesky-source-1m-best-compression "${OUTPUT_PREFIX}_bluesky-source-1m-best-compression.results_runtime"

# bluesky-source-10m-best-compression
./create_and_load.sh bluesky-source-10m-best-compression index_template_source_best_compression "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-10m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-source-10m-best-compression.data_size"
# ./benchmark.sh bluesky-source-10m-best-compression "${OUTPUT_PREFIX}_bluesky-source-10m-best-compression.results_runtime"

# bluesky-source-100m-best-compression
./create_and_load.sh bluesky-source-100m-best-compression index_template_source_best_compression "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-100m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-source-100m-best-compression.data_size"
# ./benchmark.sh bluesky-source-100m-best-compression "${OUTPUT_PREFIX}_bluesky-source-100m-best-compression.results_runtime"

# # bluesky-source-1000m-best-compression
# ./create_and_load.sh bluesky-source-1000m-best-compression index_template_source_best_compression "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1000m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-source-1000m-best-compression.data_size"
# ./benchmark.sh bluesky-source-1000m-best-compression "${OUTPUT_PREFIX}_bluesky-source-1000m-best-compression.results_runtime"

# # bluesky-source-1m-default-compression
./create_and_load.sh bluesky-source-1m-default-compression index_template_source_default_compression "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-source-1m-default-compression.data_size"
# ./benchmark.sh bluesky-source-1m-default-compression "${OUTPUT_PREFIX}_bluesky-source-1m-default-compression.results_runtime"

# # bluesky-source-10m-default-compression
./create_and_load.sh bluesky-source-10m-default-compression index_template_source_default_compression "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-10m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-source-10m-default-compression.data_size"
# ./benchmark.sh bluesky-source-10m-default-compression "${OUTPUT_PREFIX}_bluesky-source-10m-default-compression.results_runtime"

# # bluesky-source-100m-default-compression
./create_and_load.sh bluesky-source-100m-default-compression index_template_source_default_compression "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-100m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-source-100m-default-compression.data_size"
# ./benchmark.sh bluesky-source-100m-default-compression "${OUTPUT_PREFIX}_bluesky-source-100m-default-compression.results_runtime"

# # bluesky-source-1000m-default-compression
# ./create_and_load.sh bluesky-source-1000m-default-compression index_template_source_default_compression "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1000m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-source-1000m-default-compression.data_size"
# ./benchmark.sh bluesky-source-1000m-default-compression "${OUTPUT_PREFIX}_bluesky-source-1000m-default-compression.results_runtime"

# # bluesky-no-source-1m-default-compression
./create_and_load.sh bluesky-no-source-1m-default-compression index_template_no_source_default_compression "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-1m-default-compression.data_size"
# ./benchmark.sh bluesky-no-source-1m-default-compression "${OUTPUT_PREFIX}_bluesky-no-source-1m-default-compression.results_runtime"

# # bluesky-no-source-10m-default-compression
./create_and_load.sh bluesky-no-source-10m-default-compression index_template_no_source_default_compression "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-10m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-10m-default-compression.data_size"
# ./benchmark.sh bluesky-no-source-10m-default-compression "${OUTPUT_PREFIX}_bluesky-no-source-10m-default-compression.results_runtime"

# # bluesky-no-source-100m-default-compression
./create_and_load.sh bluesky-no-source-100m-default-compression index_template_no_source_default_compression "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-100m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-100m-default-compression.data_size"
# ./benchmark.sh bluesky-no-source-100m-default-compression "${OUTPUT_PREFIX}_bluesky-no-source-100m-default-compression.results_runtime"

# # bluesky-no-source-1000m-default-compression
# ./create_and_load.sh bluesky-no-source-1000m-default-compression index_template_no_source_default_compression "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1000m-default-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-1000m-default-compression.data_size"
# ./benchmark.sh bluesky-no-source-1000m-default-compression "${OUTPUT_PREFIX}_bluesky-no-source-1000m-default-compression.results_runtime"

# # bluesky-no-source-1m-best-compression
./create_and_load.sh bluesky-source-1m-best-compression index_template_no_source_best_compression "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-1m-best-compression.data_size"
# ./benchmark.sh bluesky-no-source-1m-best-compression "${OUTPUT_PREFIX}_bluesky-no-source-1m-best-compression.results_runtime"

# # bluesky-no-source-10m-best-compression
./create_and_load.sh bluesky-source-10m-best-compression index_template_no_source_best_compression "$DATA_DIRECTORY" 10 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-10m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-10m-best-compression.data_size"
# ./benchmark.sh bluesky-no-source-10m-best-compression "${OUTPUT_PREFIX}_bluesky-no-source-10m-best-compression.results_runtime"

# # bluesky-no-source-100m-best-compression
./create_and_load.sh bluesky-no-source-100m-best-compression index_template_no_source_best_compression "$DATA_DIRECTORY" 100 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-100m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-100m-best-compression.data_size"
# ./benchmark.sh bluesky-no-source-100m-best-compression "${OUTPUT_PREFIX}_bluesky-no-source-100m-best-compression.results_runtime"

# # bluesky-no-source-1000m-best-compression
# #./create_and_load.sh bluesky-no-source-1000m-best-compression index_template_no_source_best_compression "$DATA_DIRECTORY" 1000 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1000m-best-compression | tee "${OUTPUT_PREFIX}_bluesky-no-source-1000m-best-compression.data_size"
# ./benchmark.sh bluesky-no-source-1000m-best-compression "${OUTPUT_PREFIX}_bluesky-no-source-1000m-best-compression.results_runtime"