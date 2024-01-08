# Keeper Bench Suite
This respository offers an easy way to benchmark the performance of ClickHouse Keeper and Zookeeper using the [keeper-bench](https://github.com/ClickHouse/ClickHouse/tree/master/utils/keeper-bench) tool. It generates containers with different resources and sends the same workload for ClickHouse Keeper and Zookeeper. During the benchmark, the script also scrapes container metrics through cAdvisor and output of `mntr`. 

### Getting Started
Before we begin, we will need to create two tables to store information and metrics about the benchmark. After every each benchmark run, the script will write metrics collected into ClickHouse. To configure the connection, please edit the `.env_template` file accordingly and save it as `.env`.

Info table
```
CREATE TABLE default.keeper_bench_info
(
    `experiment_id` String,
    `benchmark_id` String,
    `host_info` String,
    `benchmark_ts` DateTime DEFAULT now(),
    `keeper_type` String,
    `keeper_count` UInt32,
    `keeper_container_cpu` UInt32,
    `keeper_container_memory` String,
    `keeper_jvm_memory` String,
    `exception` String,
    `keeper_bench_config_concurrency` UInt32,
    `keeper_bench_config_iterations` UInt32,
    `result_read_total_requests` UInt32,
    `result_read_requests_per_second` Float32,
    `result_read_bytes_per_second` Float32,
    `result_read_percentiles` Array(Map(String, Float32)),
    `result_write_total_requests` UInt32,
    `result_write_requests_per_second` Float32,
    `result_write_bytes_per_second` Float32,
    `result_write_percentiles` Array(Map(String, Float32)),
    `workload_file` String,
    `properties` Map(String, String)
)
ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
ORDER BY (experiment_id, benchmark_id)
SETTINGS index_granularity = 8192
```

Metric table
```
CREATE TABLE default.keeper_bench_metric
(
    `experiment_id` String,
    `benchmark_id` String,
    `container_hostname` String,
    `metric` String,
    `value` Float32,
    `prometheus_ts` DateTime64(3)
)
ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
ORDER BY (benchmark_id, container_hostname)
SETTINGS index_granularity = 8192
```

### Benchmarking

It is advisable to run this on a brand new host, and setup the Python environment with the following packages.
```
sudo DEBIAN_FRONTEND=noninteractive apt install python3-pip python3-venv -y
python3 -m venv venv
source venv/bin/activate
pip install -U clickhouse_connect==0.6.12 Jinja2 docker requests python-dotenv pandas==2.1 pyyaml
```

Also, make sure that `docker` and `docker compose` are installed. 

```
# docker -v
Docker version 24.0.6, build ed223bc

# docker compose version
Docker Compose version v2.20.3
```

Now, we can start the benchmark:

```
# python3 bench.py
```