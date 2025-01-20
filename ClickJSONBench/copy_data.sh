#!/bin/bash

echo "Select the dataset size to download:"
echo "1) 1m (default)"
echo "2) 10m"
echo "3) 100m"
echo "4) 1000m"
read -p "Enter the number corresponding to your choice: " choice

case $choice in
    2)
        # Download 10m dataset
        wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..0010}.json.gz -P ~/data/bluesky -N
        ;;
    3)
        # Download 100m dataset
        wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..0100}.json.gz -P ~/data/bluesky -N
        ;;
    4)
        # Download 1000m dataset
        wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_{0001..1000}.json.gz -P ~/data/bluesky -N
        ;;
    *)
        # Download 1m dataset
        wget https://clickhouse-public-datasets.s3.amazonaws.com/bluesky/file_0001.json.gz -P ~/data/bluesky -N
        ;;
esac