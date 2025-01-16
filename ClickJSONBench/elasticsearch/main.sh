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

# bluesky-source-1m-deflate
./create_and_load.sh bluesky-source-1m-best-compression index_template_source_best_compression "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1m-deflate | tee "${OUTPUT_PREFIX}_bluesky-source-1m-deflate.data_size"
# ./benchmark.sh bluesky-source-1m-deflate "${OUTPUT_PREFIX}_bluesky-source-1m-deflate.results_runtime"

# # bluesky-source-10m-deflate
# #./create_and_load.sh bluesky-source-10m-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-10m-deflate | tee "${OUTPUT_PREFIX}_bluesky-source-10m-deflate.data_size"
# ./benchmark.sh bluesky-source-10m-deflate "${OUTPUT_PREFIX}_bluesky-source-10m-deflate.results_runtime"

# # bluesky-source-100m-deflate
# #./create_and_load.sh bluesky-source-100m-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-100m-deflate | tee "${OUTPUT_PREFIX}_bluesky-source-100m-deflate.data_size"
# ./benchmark.sh bluesky-source-100m-deflate "${OUTPUT_PREFIX}_bluesky-source-100m-deflate.results_runtime"

# # bluesky-source-1b-deflate
# #./create_and_load.sh bluesky-source-1b-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1b-deflate | tee "${OUTPUT_PREFIX}_bluesky-source-1b-deflate.data_size"
# ./benchmark.sh bluesky-source-1b-deflate "${OUTPUT_PREFIX}_bluesky-source-1b-deflate.results_runtime"

# # bluesky-source-1m-lz4
# #./create_and_load.sh bluesky-source-1m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-source-1m-lz4.data_size"
# ./benchmark.sh bluesky-source-1m-deflate "${OUTPUT_PREFIX}_bluesky-source-1m-lz4.results_runtime"

# # bluesky-source-10m-lz4
# #./create_and_load.sh bluesky-source-10m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-10m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-source-10m-lz4.data_size"
# ./benchmark.sh bluesky-source-10m-lz4 "${OUTPUT_PREFIX}_bluesky-source-10m-lz4.results_runtime"

# # bluesky-source-100m-lz4
# #./create_and_load.sh bluesky-source-100m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-100m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-source-100m-lz4.data_size"
# ./benchmark.sh bluesky-source-100m-lz4 "${OUTPUT_PREFIX}_bluesky-source-100m-lz4.results_runtime"

# # bluesky-source-1000m-lz4
# #./create_and_load.sh bluesky-source-1b-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-source-1b-lz4 | tee "${OUTPUT_PREFIX}_bluesky-source-1b-lz4.data_size"
# ./benchmark.sh bluesky-source-1b-lz4 "${OUTPUT_PREFIX}_bluesky-source-1b-lz4.results_runtime"

# # bluesky-no-source-1m-lz4
# #./create_and_load.sh bluesky-no-source-1m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-no-source-1m-lz4.data_size"
# ./benchmark.sh bluesky-no-source-1m-deflate "${OUTPUT_PREFIX}_bluesky-no-source-1m-lz4.results_runtime"

# # bluesky-no-source-10m-lz4
# #./create_and_load.sh bluesky-no-source-10m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-10m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-no-source-10m-lz4.data_size"
# ./benchmark.sh bluesky-no-source-10m-lz4 "${OUTPUT_PREFIX}_bluesky-no-source-10m-lz4.results_runtime"

# # bluesky-no-source-100m-lz4
# #./create_and_load.sh bluesky-no-source-100m-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-100m-lz4 | tee "${OUTPUT_PREFIX}_bluesky-no-source-100m-lz4.data_size"
# ./benchmark.sh bluesky-no-source-100m-lz4 "${OUTPUT_PREFIX}_bluesky-no-source-100m-lz4.results_runtime"

# # bluesky-no-source-1000m-lz4
# #./create_and_load.sh bluesky-no-source-1b-lz4  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1b-lz4 | tee "${OUTPUT_PREFIX}_bluesky-no-source-1b-lz4.data_size"
# ./benchmark.sh bluesky-no-source-1b-lz4 "${OUTPUT_PREFIX}_bluesky-no-source-1b-lz4.results_runtime"

# # bluesky-no-source-1m-deflate
# #./create_and_load.sh bluesky-source-1m-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1m-deflate | tee "${OUTPUT_PREFIX}_bluesky-no-source-1m-deflate.data_size"
# ./benchmark.sh bluesky-no-source-1m-deflate "${OUTPUT_PREFIX}_bluesky-no-source-1m-deflate.results_runtime"

# # bluesky-no-source-10m-deflate
# #./create_and_load.sh bluesky-source-10m-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-10m-deflate | tee "${OUTPUT_PREFIX}_bluesky-no-source-10m-deflate.data_size"
# ./benchmark.sh bluesky-no-source-10m-deflate "${OUTPUT_PREFIX}_bluesky-no-source-10m-deflate.results_runtime"

# # bluesky-no-source-100m-deflate
# #./create_and_load.sh bluesky-no-source-100m-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-100m-deflate | tee "${OUTPUT_PREFIX}_bluesky-no-source-100m-deflate.data_size"
# ./benchmark.sh bluesky-no-source-100m-deflate "${OUTPUT_PREFIX}_bluesky-no-source-100m-deflate.results_runtime"

# # bluesky-no-source-1b-deflate
# #./create_and_load.sh bluesky-no-source-1b-deflate  "$DATA_DIRECTORY" 1 "$SUCCESS_LOG" "$ERROR_LOG"
# ./total_size.sh bluesky-no-source-1b-deflate | tee "${OUTPUT_PREFIX}_bluesky-no-source-1b-deflate.data_size"
# ./benchmark.sh bluesky-no-source-1b-deflate "${OUTPUT_PREFIX}_bluesky-no-source-1b-deflate.results_runtime"