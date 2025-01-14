#!/bin/bash

# Default data directory
DEFAULT_DATA_DIRECTORY=~/data/bluesky

# Allow the user to optionally provide the data directory as an argument
DATA_DIRECTORY="${1:-$DEFAULT_DATA_DIRECTORY}"

# Check if the directory exists
if [[ ! -d "$DATA_DIRECTORY" ]]; then
    echo "Error: Data directory '$DATA_DIRECTORY' does not exist."
    exit 1
fi

chmod +x ./*.sh

./install.sh

# bluesky_1m_lz4
./create_and_load.sh bluesky_1m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1 success.log error.log
./data_size.sh bluesky_1m_lz4 bluesky | tee _m6i.8xlarge_bluesky_1m_lz4.data_size
./benchmark.sh bluesky_1m_lz4 | tee _m6i.8xlarge_bluesky_1m_lz4.result

# bluesky_10m_lz4
./create_and_load.sh bluesky_10m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_lz4 bluesky | tee _m6i.8xlarge_bluesky_10m_lz4.data_size
./benchmark.sh bluesky_10m_lz4 | tee _m6i.8xlarge_bluesky_10m_lz4.result

# bluesky_100m_lz4
./create_and_load.sh bluesky_100m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_lz4 bluesky | tee _m6i.8xlarge_bluesky_100m_lz4.data_size
./benchmark.sh bluesky_100m_lz4 | tee _m6i.8xlarge_bluesky_100m_lz4.result

# bluesky_1000m_lz4
./create_and_load.sh bluesky_1000m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_lz4 bluesky | tee _m6i.8xlarge_bluesky_1000m_lz4.data_size
./benchmark.sh bluesky_1000m_lz4 | tee _m6i.8xlarge_bluesky_1000m_lz4.result

# bluesky_1m_zstd
./create_and_load.sh bluesky_1m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 1 success.log error.log
./data_size.sh bluesky_1m_zstd bluesky | tee _m6i.8xlarge_bluesky_1m_zstd.data_size
./benchmark.sh bluesky_1m_zstd | tee _m6i.8xlarge_bluesky_1m_zstd.result

# bluesky_10m_zstd
./create_and_load.sh bluesky_10m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_zstd bluesky | tee _m6i.8xlarge_bluesky_10m_zstd.data_size
./benchmark.sh bluesky_10m_zstd | tee _m6i.8xlarge_bluesky_10m_zstd.result

# bluesky_100m_zstd
./create_and_load.sh bluesky_100m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_zstd bluesky | tee _m6i.8xlarge_bluesky_100m_zstd.data_size
./benchmark.sh bluesky_100m_zstd | tee _m6i.8xlarge_bluesky_100m_zstd.result

# bluesky_1000m_zstd
./create_and_load.sh bluesky_1000m_zstd bluesky ddl_zstd.sql "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_zstd bluesky | tee _m6i.8xlarge_bluesky_1000m_zstd.data_size
./benchmark.sh bluesky_1000m_zstd | tee _m6i.8xlarge_bluesky_1000m_zstd.result