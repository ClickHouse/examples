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
./benchmark bluesky_1m_lz4 | tee _m6i.8xlarge_bluesky_1m_lz4.result

# bluesky_10m_lz4
./create_and_load.sh bluesky_10m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_lz4 bluesky | tee _m6i.8xlarge_bluesky_10m_lz4.data_size
./benchmark bluesky_10m_lz4 | tee _m6i.8xlarge_bluesky_10m_lz4.result

# bluesky_100m_lz4
./create_and_load.sh bluesky_100m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_lz4 bluesky | tee _m6i.8xlarge_bluesky_100m_lz4.data_size
./benchmark bluesky_100m_lz4 | tee _m6i.8xlarge_bluesky_100m_lz4.result

# bluesky_1000m_lz4
./create_and_load.sh bluesky_1000m_lz4 bluesky ddl_lz4.sql "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_lz4 bluesky | tee _m6i.8xlarge_bluesky_1000m_lz4.data_size
./benchmark bluesky_1000m_lz4 | tee _m6i.8xlarge_bluesky_1000m_lz4.result

# bluesky_1m_pglz
./create_and_load.sh bluesky_1m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 1 success.log error.log
./data_size.sh bluesky_1m_pglz bluesky | tee _m6i.8xlarge_bluesky_1m_pglz.data_size
./benchmark bluesky_1m_pglz | tee _m6i.8xlarge_bluesky_1m_pglz.result

# bluesky_10m_pglz
./create_and_load.sh bluesky_10m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 10 success.log error.log
./data_size.sh bluesky_10m_pglz bluesky | tee _m6i.8xlarge_bluesky_10m_pglz.data_size
./benchmark bluesky_10m_pglz | tee _m6i.8xlarge_bluesky_10m_pglz.result

# bluesky_100m_pglz
./create_and_load.sh bluesky_100m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 100 success.log error.log
./data_size.sh bluesky_100m_pglz bluesky | tee _m6i.8xlarge_bluesky_100m_pglz.data_size
./benchmark bluesky_100m_pglz | tee _m6i.8xlarge_bluesky_100m_pglz.result

# bluesky_1000m_pglz
./create_and_load.sh bluesky_1000m_pglz bluesky ddl_pglz.sql "$DATA_DIRECTORY" 1000 success.log error.log
./data_size.sh bluesky_1000m_pglz bluesky | tee _m6i.8xlarge_bluesky_1000m_pglz.data_size
./benchmark bluesky_1000m_pglz | tee _m6i.8xlarge_bluesky_1000m_pglz.result