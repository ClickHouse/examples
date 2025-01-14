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

# bluesky_1m_snappy
./create_and_load.sh bluesky_1m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 1 success.log error.log
./data_size.sh bluesky_1m_snappy bluesky | tee _m6i.8xlarge_bluesky_1m_snappy.data_size
./benchmark bluesky_1m_snappy | tee _m6i.8xlarge_bluesky_1m_snappy.result

# bluesky_10m_snappy
./create_and_load.sh bluesky_10m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_snappy bluesky | tee _m6i.8xlarge_bluesky_10m_snappy.data_size
./benchmark bluesky_10m_snappy | tee _m6i.8xlarge_bluesky_10m_snappy.result

# bluesky_100m_snappy
./create_and_load.sh bluesky_100m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_snappy bluesky | tee _m6i.8xlarge_bluesky_100m_snappy.data_size
./benchmark bluesky_100m_snappy | tee _m6i.8xlarge_bluesky_100m_snappy.result

# bluesky_1000m_snappy
./create_and_load.sh bluesky_1000m_snappy bluesky ddl_snappy.js "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_snappy bluesky | tee _m6i.8xlarge_bluesky_1000m_snappy.data_size
./benchmark bluesky_1000m_snappy | tee _m6i.8xlarge_bluesky_1000m_snappy.result

# bluesky_1m_zstd
./create_and_load.sh bluesky_1m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 1 success.log error.log
./data_size.sh bluesky_1m_zstd bluesky | tee _m6i.8xlarge_bluesky_1m_zstd.data_size
./benchmark bluesky_1m_zstd | tee _m6i.8xlarge_bluesky_1m_zstd.result

# bluesky_10m_zstd
./create_and_load.sh bluesky_10m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_zstd bluesky | tee _m6i.8xlarge_bluesky_10m_zstd.data_size
./benchmark bluesky_10m_zstd | tee _m6i.8xlarge_bluesky_10m_zstd.result

# bluesky_100m_zstd
./create_and_load.sh bluesky_100m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_zstd bluesky | tee _m6i.8xlarge_bluesky_100m_zstd.data_size
./benchmark bluesky_100m_zstd | tee _m6i.8xlarge_bluesky_100m_zstd.result

# bluesky_1000m_zstd
./create_and_load.sh bluesky_1000m_zstd bluesky ddl_zstd.js "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_zstd bluesky | tee _m6i.8xlarge_bluesky_1000m_zstd.data_size
./benchmark bluesky_1000m_zstd | tee _m6i.8xlarge_bluesky_1000m_zstd.result