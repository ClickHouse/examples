#!/bin/bash

# Uncomment one of the wget command to download the dataset of your choice - By default, the 1m dataset is downloaded

# Download 1m dataset
wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_0001.json.gz -P ~/data/bluesky

# Download 10m dataset
#wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..0010}.json.gz -P ~/data/bluesky

# Download 100m dataset
#wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..0100}.json.gz -P ~/data/bluesky

# Download 1000m dataset
#wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..1000}.json.gz -P ~/data/bluesky