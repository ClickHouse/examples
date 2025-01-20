# ClickJSONBench: A Benchmark for native JSON support on Analytical Databases

## Overview 

This benchmark compares the native support JSON of most popular analytical databases. 

The dataset is a collection of files containing JSON objects delimited by newline (ndjson). This was obtained using Jetstream to collect Bluesky events. The dataset contains 1 billion Bluesky events and is currently hosted on a public S3 bucket. 

## Pre-requisites 

To run the benchmark will 1 billion rows, it is important to provision a machine with sufficient resources and disk space. The full compressed dataset takes 125 Gb of disk space, uncompressed it takes up to 425 Gb. 

For reference, the initial benchmarks have been run on the following machines: 
- AWS EC2 instance: m6i.8xlarge
- Disk: > 10Tb gp3
- OS: Ubuntu 24.04

If you're interested in running the full benchmark, be aware that it will takes several hours, or days depending on the database. 

## Usage 

Each folder contains the scripts required to run the benchmark on a database, by example [clickhouse](./clickhouse/) folder contains the scripts to run the benchmark on ClickHouse.

The full dataset contains 1 billion rows, but the benchmark runs for different dataset sizes (1 million, 10 million, 100 million and 1 billion rows) in order to compare results at different scale. 

### Download the data

Start by downloading the dataset using the script [`copy_data.sh`](./copy_data.sh). When running the script, you will be prompted the dataset size you want to download, if you just want to test it out, I'd recommend starting with the default 1m rows, if you're interested to reproduce results at scale, go with the full dataset, 1 billion rows. 

```
ubuntu@8971ec18ce06:/mnt/test# ./copy_data.sh 
Select the dataset size to download:
1) 1m (default)
2) 10m
3) 100m
4) 1000m
Enter the number corresponding to your choice: 
```

### Run the benchmark

Navigate to the folder corresponding to the database you want to run the benchmark for. 

The script `main.sh` is the script to run each benchmark. 

Usage: `main.sh <DATA_DIRECTORY> <SUCCESS_LOG> <ERROR_LOG> <OUTPUT_PREFIX>`

- `<DATA_DIRECTORY>`: The directory where the dataset is stored. Default is `~/data/bluesky`.
- `<SUCCESS_LOG>`: The file to log successful operations. Default is `success.log`.
- `<ERROR_LOG>`: The file to log errors. Default is `error.log`.
- `<OUTPUT_PREFIX>`: The prefix for output files. Default is `_m6i.8xlarge`.

By example for clickhouse:

```
cd clickhouse
./main.sh 

Select the dataset size to benchmark:
1) 1m (default)
2) 10m
3) 100m
4) 1000m
5) all
Enter the number corresponding to your choice: 
```

Enter the dataset size you want to run the benchmark for, then hit enter. 

### Retrieve results

The results of the benchmark are stored within each folder in files prefixed with the $OUTPUT_PREFIX (Default is `_m6i.8xlarge`).

Below is a description of the files that might be generated as a result of the benchmark. Depending on the database, some files might not be generated because not relevant. 

- `.total_size`: Contains the total size of the dataset.
- `.data_size`: Contains the data size of the dataset.
- `.index_size`: Contains the index size of the dataset.
- `.index_usage`: Contains the index usage statistics.
- `.physical_query_plans`: Contains the physical query plans.
- `.results_runtime`: Contains the runtime results of the benchmark.
- `.results_memory_usage`: Contains the memory usage results of the benchmark.


