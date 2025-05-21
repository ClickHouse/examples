# Hot table data caching in traditional shared-nothing ClickHouse Clusters


## Data set

We’ll use the [Amazon customer reviews](https://clickhouse.com/docs/getting-started/example-datasets/amazon-reviews) dataset, which has around 150 million product reviews from 1995 to 2015.


## Hardware and software

We’re running ClickHouse 25.5 on an AWS `m6i.8xlarge` EC2 instance with:
- 32 vCPUs
- 128 GiB RAM
- 1 TiB gp3 SSD (16000 IOPS, 1000 MiB/s max throughput) 
- Ubuntu Linux 24.04

## Table DDL and data loading

We first created the Amazon reviews table:

```sql
CREATE TABLE amazon.amazon_reviews
(
    `review_date` Date CODEC(ZSTD(1)),
    `marketplace` LowCardinality(String) CODEC(ZSTD(1)),
    `customer_id` UInt64 CODEC(ZSTD(1)),
    `review_id` String CODEC(ZSTD(1)),
    `product_id` String CODEC(ZSTD(1)),
    `product_parent` UInt64 CODEC(ZSTD(1)),
    `product_title` String CODEC(ZSTD(1)),
    `product_category` LowCardinality(String) CODEC(ZSTD(1)),
    `star_rating` UInt8 CODEC(ZSTD(1)),
    `helpful_votes` UInt32 CODEC(ZSTD(1)),
    `total_votes` UInt32 CODEC(ZSTD(1)),
    `vine` Bool CODEC(ZSTD(1)),
    `verified_purchase` Bool CODEC(ZSTD(1)),
    `review_headline` String CODEC(ZSTD(1)),
    `review_body` String CODEC(ZSTD(1))
)
ENGINE = MergeTree
ORDER BY (review_date, product_category);
```

And then loaded the dataset from Parquet files hosted in our public example datasets S3 bucket:

```sql
INSERT INTO  amazon.amazon_reviews
SELECT * FROM s3(
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
│ 150.96 million │           76 │                 32 │
└────────────────┴──────────────┴────────────────────┘
```

## Dropping the os-level page cache
```
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
```

## Bypassing the os-level page cache
You can force ClickHouse to always read all data directly from storage (even when it is cached in the page cache) by setting the [min_bytes_to_use_direct_io](https://clickhouse.com/docs/operations/settings/settings#min_bytes_to_use_direct_io) setting to `1`.

For example:
```sql
SELECT ... FROM ... SETTINGS min_bytes_to_use_direct_io = 1;
```




## Cold query run
We drop the page cache - see above - and run the example query:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*);
```

We use the [ignore](https://clickhouse.com/docs/sql-reference/functions/other-functions#ignore) function do 'touch' each row from each column aka full table scan.

This is the `clickhouse-client` output for the cold query run:
```text
Query id: a9ca493f-15c1-4034-a423-b46c9381581b

   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘

1 row in set. Elapsed: 29.693 sec. Processed 150.96 million rows, 81.61 GB (5.08 million rows/s., 2.75 GB/s.)
Peak memory usage: 1001.93 MiB.
```

Note that the throughput numbers (e.g. `2.75 GB/s`) reported by `clickhouse-client` are logical numbers based on the **uncompressed** data.

## Checking page cache usage for cold query run
We fetch page cache usage infos for the query run above from the query log system table by using the printed query id for the run above:

```sql
SELECT
    round(ProfileEvents['ThreadPoolReaderPageCacheMissBytes'] / 1e9) AS page_cache_miss_GB,
    round(ProfileEvents['ThreadPoolReaderPageCacheHitBytes'] / 1e9) AS page_cache_hit_GB,
    ProfileEvents['ConcurrencyControlSlotsAcquired'] AS parallel_streams
FROM system.query_log
WHERE (query_id = 'a9ca493f-15c1-4034-a423-b46c9381581b') AND (type = 'QueryFinish');
```

```text
┌─page_cache_miss_GB─┬─page_cache_hit_GB─┬─parallel_streams─┐
│                 32 │                 0 │               32 │
└────────────────────┴───────────────────┴──────────────────┘
```

We can see that none of the compressed hot table data was cached.

Additionally, during the cold query run, we observed the disk read throughput on our ec2 test machine:

```text
dstat -dD total,nvme0n1  1

 read
   0 
  20M
1992M
1006M
1006M
1006M
1005M
1005M
1003M
1006M
1006M
1006M
1006M
1003M
1006M
1006M
1006M
1006M
1003M
1006M
1006M
1006M
1006M
1006M
1006M
1002M
1006M
1006M
1006M
1006M
1006M
 611M
   0 
```

We can see that during all of the ~30 seconds of running the query with cold caches, data was read from the disk with max throughput (1000 MiB/s).



## Hot query run
We run the same example query a second time:
```sql
SELECT count()
FROM amazon_reviews
WHERE NOT ignore(*);
```


This is the `clickhouse-client` output for the hot query run:
```text
Query id: e488a037-268a-4a6b-89fe-caa870fec0da
   ┌───count()─┐
1. │ 150957260 │ -- 150.96 million
   └───────────┘
1 row in set. Elapsed: 5.411 sec. Processed 150.96 million rows, 81.61 GB (27.90 million rows/s., 15.08 GB/s.)
Peak memory usage: 622.74 MiB.
```


## Checking page cache usage for hot query run
We fetch page cache usage infos for the query run above from the query log system table by using the printed query id for the run above:

```sql
SELECT
    round(ProfileEvents['ThreadPoolReaderPageCacheMissBytes'] / 1e9) AS page_cache_miss_GB,
    round(ProfileEvents['ThreadPoolReaderPageCacheHitBytes'] / 1e9) AS page_cache_hit_GB,
    ProfileEvents['ConcurrencyControlSlotsAcquired'] AS parallel_streams
FROM system.query_log
WHERE (query_id = 'e488a037-268a-4a6b-89fe-caa870fec0da') AND (type = 'QueryFinish');
```

```text
┌─page_cache_miss_GB─┬─page_cache_hit_GB─┬─parallel_streams─┐
│                  0 │                32 │               32 │
└────────────────────┴───────────────────┴──────────────────┘
```

We can see that all of the compressed hot table data was cached.

Additionally, during the hot query run, we observed the disk read throughput on our ec2 test machine:

```text
dstat -dD total,nvme0n1  1

 read
   0 
   0 
   0 
   0 
   0 
   0 
```

We can see that during all of the ~5 seconds of running the query with hot caches, no data was read from the disk.