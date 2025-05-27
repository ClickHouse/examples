# Hot table data caching with ClickHouse Cloud's new distributed cache


## Data set

We’ll use the [Amazon customer reviews](https://clickhouse.com/docs/getting-started/example-datasets/amazon-reviews) dataset, which has around 150 million product reviews from 1995 to 2015.


## Hardware and software

We’re running a ClickHouse Cloud service deployed on AWS eu-west-1 with 6 compute nodes:
- 30 vCPUs per node
- 120 GiB RAM per node
- ClickHouse Version 25.4

## Table DDL and data loading

We first created the Amazon reviews table:

```sql
CREATE TABLE amazon.amazon_reviews
(
    `review_date` Date,
    `marketplace` LowCardinality(String),
    `customer_id` UInt64,
    `review_id` String,
    `product_id` String,
    `product_parent` UInt64,
    `product_title` String,
    `product_category` LowCardinality(String),
    `star_rating` UInt8,
    `helpful_votes` UInt32,
    `total_votes` UInt32,
    `vine` Bool,
    `verified_purchase` Bool,
    `review_headline` String,
    `review_body` String
)
ENGINE = MergeTree
ORDER BY (review_date, product_category);
```

And then loaded the dataset from Parquet files hosted in our public example datasets S3 bucket:

```sql
INSERT INTO  amazon.amazon_reviews
SELECT * FROM s3Cluster('default',
'https://datasets-documentation.s3.eu-west-3.amazonaws.com/amazon_reviews/amazon_reviews_*.snappy.parquet');

```

## Table size

We check the table’s size after loading:
```sql
SELECT
    formatReadableQuantity(sum(rows)) AS rows,
    round(sum(data_uncompressed_bytes) / 1e9) AS data_size_gb,
    round(sum(data_compressed_bytes) / 1e9) AS compressed_size_gb
FROM system.parts
WHERE active AND database = 'amazon' AND table = 'amazon_reviews';
```

```text
┌─rows───────────┬─data_size_gb─┬─compressed_size_gb─┐
│ 150.96 million │           77 │                 32 │
└────────────────┴──────────────┴────────────────────┘
```


## Throughput benchmark: Full table scan

### Initial warm-up run - cold - single node

We just ingested the data with a specific node and parallel replicas / ...cluster function disabled, into a fresh new table with a node in AZ1.

Then we re-connect with clickhouse-client until we are connected to a node in a different AZ.

That ensures the distributed cache is cold for that table and node.


Now we run the test query:

```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 0;
```

We use the [ignore](https://clickhouse.com/docs/sql-reference/functions/other-functions#ignore) function do 'touch' each row from each column aka full table scan.

This is the `clickhouse-client` output for the cold query run:

```text
Query id: 6ddd9776-cddd-4396-9773-d2bf1af7e40b
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 19.081 sec. Processed 150.96 million rows, 81.61 GB (7.91 million rows/s., 4.28 GB/s.)
Peak memory usage: 1.30 GiB.
```

Note that the throughput numbers (e.g. `4.28 GB/s`) reported by `clickhouse-client` are logical numbers based on the **uncompressed** data.




### Initial warm-up run - hot - single node
We run the same example query a second time:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 0;
```


This is the `clickhouse-client` output for the hot query run:
```text
Query id: 8c6d4605-6e50-43ab-8e9d-deccef9ac3bd
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 3.893 sec. Processed 150.96 million rows, 81.61 GB (38.78 million rows/s., 20.96 GB/s.)
Peak memory usage: 915.75 MiB.
```


### Subsequent node run - cold - single node

Note: Ensure that it's either 
- (1) a different node within the same AZ, or 
- (2) just restart the service, and query with the same node as before


We did (2):

- Check hostname of current node that we used for initial warm up above:
```sql
SELECT hostname();
````

```text
   ┌─hostname()─────────────────────┐
1. │ c-camel-oa-93-server-626huh8-0 │
   └────────────────────────────────┘
````

- Restart service


- Connect with clickhouse-client and check hostname until we have a match...
```sql
SELECT hostname();
````

```text
   ┌─hostname()─────────────────────┐
1. │ c-camel-oa-93-server-626huh8-0 │
   └────────────────────────────────┘
````


- Run the query:

```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 0;
```

```text
Query id: 7cdc9ae5-6005-4fee-9d38-3022909b0597
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 10.280 sec. Processed 15
Peak memory usage: 1.35 GiB.
```

### Subsequent node run - hot - single node
We run the same example query a second time:

```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 0;
```

```text
Query id: 2aa20e49-3a05-4b44-9929-a7eb3f3de2d2
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 3.806 sec. Processed 150.96 million rows, 81.61 GB (39.66 million rows/s., 21.44 GB/s.)
Peak memory usage: 906.23 MiB.
```






### 6 subsequent parallel nodes - cold run

We restart the whole service first to ensure that all userspace page caches are cold on all 6 compute nodes of our test service.

Then we run the example query with parallel replicas enabled.

```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 1;
```

```text
Query id: 868189a1-a3e9-45df-9429-9d18a829281a
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 4.466 sec. Processed 150.96 million rows, 81.61 GB (33.80 million rows/s., 18.27 GB/s.)
Peak memory usage: 1.10 GiB.
```


### 6 subsequent parallel nodes - hot run

We run the query a second time with parallel replicas enables

```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS 
    read_through_distributed_cache = 1,
    use_page_cache_with_distributed_cache = 1,
    enable_parallel_replicas = 1;
```

```text
Query id: 4a22bc8f-6888-4a24-a0a3-56007fb02348
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 0.758 sec. Processed 150.96 million rows, 81.61 GB (199.25 million rows/s., 107.71 GB/s.)
Peak memory usage: 928.47 MiB.
```


## Latency benchmark: Scattered reads

We use this example query

```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
FORMAT Null;
```

With trace logging enabled:
```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
SETTINGS send_logs_level = 'trace'
```

```text
...
20 marks to read from 3 ranges
...
```

That is very little data and ranges - impossible to hide latency with parallel I/O...


### Initial warm-up run - cold - single node

We just ingested the data with a specific node and parallel replicas / ...cluster function disabled, into a fresh new table with a node in AZ1.

Then we re-connect with clickhouse-client until we are connected to a node in a different AZ.

That ensures the distributed cache is cold for that table and node.


Now we run the test query:
```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
FORMAT Null
SETTINGS
    enable_parallel_replicas = 0;
```

```text
Query id: d9baf038-6d7a-4e48-b8ad-3a50a666b23b
Ok.
0 rows in set. Elapsed: 0.415 sec. Processed 163.84 thousand rows, 59.87 MB (395.14 thousand rows/s., 144.38 MB/s.)
Peak memory usage: 71.04 MiB.
```

### Initial warm-up run - hot - single node

We run the query a second time
```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
FORMAT Null
SETTINGS
    enable_parallel_replicas = 0;
```

```text
Query id: cf4fd75d-3453-4322-9792-e49166095090
Ok.
0 rows in set. Elapsed: 0.059 sec. Processed 163.84 thousand rows, 59.87 MB (2.79 million rows/s., 1.02 GB/s.)
Peak memory usage: 47.81 MiB.
```

### Subsequent node run - cold - single node

Note: Ensure that it's either 
- (1) a different node within the same AZ, or 
- (2) just restart the service, and query with the same node as before


We did (2):

- Check hostname of current node that we used for initial warm up above:
```sql
SELECT hostname();
````

```text
   ┌─hostname()─────────────────────┐
1. │ c-camel-oa-93-server-626huh8-0 │
   └────────────────────────────────┘
````

- Restart service


- Connect with clickhouse-client and check hostname until we have a match...
```sql
SELECT hostname();
````

```text
   ┌─hostname()─────────────────────┐
1. │ c-camel-oa-93-server-626huh8-0 │
   └────────────────────────────────┘
````


- Run the query:
```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
FORMAT Null
SETTINGS
    enable_parallel_replicas = 0;
```

```text
Query id: 2fca592e-5bb0-4807-af45-dfd329869f92
Ok.
0 rows in set. Elapsed: 0.216 sec. Processed 163.84 thousand rows, 59.87 MB (757.07 thousand rows/s., 276.62 MB/s.)
Peak memory usage: 69.32 MiB.
```

### Subsequent node run - hot - single node

We run the query a second time:

```sql
SELECT *
FROM amazon.amazon_reviews
WHERE review_date in ['1995-06-24', '2015-06-24']
FORMAT Null
SETTINGS
    enable_parallel_replicas = 0;
```

```text
Query id: ab54389e-aac3-479b-9b78-1ff3b101ced4
Ok.
0 rows in set. Elapsed: 0.059 sec. Processed 163.84 thousand rows, 59.87 MB (2.77 million rows/s., 1.01 GB/s.)
Peak memory usage: 47.49 MiB.
```

