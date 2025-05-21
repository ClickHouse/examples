# Hot table data caching in traditional ClickHouse Cloud service


## Data set

We’ll use the [Amazon customer reviews](https://clickhouse.com/docs/getting-started/example-datasets/amazon-reviews) dataset, which has around 150 million product reviews from 1995 to 2015.


## Hardware and software

We’re running a ClickHouse Cloud service deployed on AWS eu-west-1 with 3 compute nodes:
- 30 vCPUs per node
- 120 GiB RAM per node
- ClickHouse Version 24.12

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

## Dropping the filesystem cache
```
SYSTEM DROP FILESYSTEM CACHE ON CLUSTER 'default';
```

## Bypassing the filesystem cache
You can force ClickHouse to always read all data directly from storage (even when it is cached in the filesystem cache) by setting the [enable_filesystem_cache](https://clickhouse.com/docs/operations/settings/settings#enable_filesystem_cache) setting to `0`.

For example:
```sql
SELECT ... FROM ... SETTINGS enable_filesystem_cache = 0;
```




## Cold query run - single node
We drop the filesystem cache - see above - and run the example query:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS enable_parallel_replicas = 0;
```

We use the [ignore](https://clickhouse.com/docs/sql-reference/functions/other-functions#ignore) function do 'touch' each row from each column aka full table scan.

This is the `clickhouse-client` output for the cold query run:
```text
Query id: 217e4060-b1bc-4cca-9700-1766347ff99d

   ┌───count()─┐
1. │ 150957260 │
   └───────────┘

1 row in set. Elapsed: 18.749 sec. Processed 150.96 million rows, 81.61 GB (8.05 million rows/s., 4.35 GB/s.)
Peak memory usage: 1.36 GiB.
```

Note that the throughput numbers (e.g. `4.35 GB/s`) reported by `clickhouse-client` are logical numbers based on the **uncompressed** data.

## Checking filesystem cache usage for cold query run
We fetch filesystem cache usage infos for the query run above from the query log system table by using the printed query id for the run above:

```sql
SELECT
    round(ProfileEvents['CachedReadBufferReadFromSourceBytes'] / 1e9) AS filesystem_cache_miss_GB,
    round(ProfileEvents['CachedReadBufferReadFromCacheBytes'] / 1e9) AS filesystem_cache_hit_GB
FROM clusterAllReplicas(default, system.query_log)
WHERE (query_id = '217e4060-b1bc-4cca-9700-1766347ff99d') AND (type = 'QueryFinish');
```

```text
┌─filesystem_cache_miss_GB─┬─filesystem_cache_hit_GB─┐
│                       25 │                      11 │
└──────────────────────────┴─────────────────────────┘
```

We can see that 11 of the compressed hot table data was cached. Although we dropped the cache before running the query. Reason is that ClickHouse Cloud asynchronously fetched (11 GB of) data into to cache while the query was running, before the query had to process that part of the data.





## Hot query run - single node
We run the same example query a second time:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS enable_parallel_replicas = 0;
```


This is the `clickhouse-client` output for the hot query run:
```text
Query id: b6f29ac0-1f3e-4b66-8e40-95dd1578e7b8

   ┌───count()─┐
1. │ 150957260 │
   └───────────┘
   
1 row in set. Elapsed: 3.838 sec. Processed 150.96 million rows, 81.61 GB (39.33 million rows/s., 21.26 GB/s.)
Peak memory usage: 1.26 GiB.
```


## Checking filesystem cache usage for hot query run
We fetch filesystem cache usage infos for the query run above from the query log system table by using the printed query id for the run above:

```sql
SELECT
    round(ProfileEvents['CachedReadBufferReadFromSourceBytes'] / 1e9) AS filesystem_cache_miss_GB,
    round(ProfileEvents['CachedReadBufferReadFromCacheBytes'] / 1e9) AS filesystem_cache_hit_GB
FROM clusterAllReplicas(default, system.query_log)
WHERE (query_id = 'b6f29ac0-1f3e-4b66-8e40-95dd1578e7b8') AND (type = 'QueryFinish');
```

```text
┌─filesystem_cache_miss_GB─┬─filesystem_cache_hit_GB─┐
│                        0 │                      32 │
└──────────────────────────┴─────────────────────────┘
```



## Cold query run - parallel replicas (3 nodes in parallel)
We drop the filesystem cache - see above - and run the example query:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS enable_parallel_replicas = 1;
```

We use the [ignore](https://clickhouse.com/docs/sql-reference/functions/other-functions#ignore) function do 'touch' each row from each column aka full table scan.

This is the `clickhouse-client` output for the cold query run:
```text
   ┌───count()─┐
1. │ 150957260 │
   └───────────┘

1 row in set. Elapsed: 7.598 sec. Processed 150.96 million rows, 81.61 GB (19.87 million rows/s., 10.74 GB/s.)
Peak memory usage: 1.38 GiB.
```

## Hot query run - parallel replicas (3 nodes in parallel)
We run the same example query a second time:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*)
SETTINGS enable_parallel_replicas = 1;
```


This is the `clickhouse-client` output for the hot query run:
```text
   ┌───count()─┐
1. │ 150957260 │
   └───────────┘
   
1 row in set. Elapsed: 1.712 sec. Processed 150.96 million rows, 81.61 GB (88.18 million rows/s., 47.67 GB/s.)
Peak memory usage: 1.40 GiB.
```


