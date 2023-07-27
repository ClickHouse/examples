# ClickHouse and S3 Minio

1 single ClickHouse Instance configured with 1 S3 Minio instance

This recipe defines a S3 type disk pointing to the Minio S3 instance, a storage policy that makes use of the s3 disk and a MergeTree table backed by it.

```sql
ch_minio_s3 :) SELECT * FROM trips_s3 LIMIT 1 FORMAT Vertical

SELECT *
FROM trips_s3
LIMIT 1
FORMAT Vertical

Query id: 32c7d679-183c-4d5c-a7b3-f5f0f567b23f

Row 1:
──────
trip_id:           14
pickup_date:       2013-08-02
pickup_datetime:   2013-08-02 09:43:58
dropoff_datetime:  2013-08-02 09:44:13
pickup_longitude:  0
pickup_latitude:   0
dropoff_longitude: 0
dropoff_latitude:  0
passenger_count:   1
trip_distance:     0
tip_amount:        0
total_amount:      2
payment_type:      CSH

1 row in set. Elapsed: 0.017 sec. Processed 1.06 thousand rows, 67.90 KB (61.98 thousand rows/s., 3.97 MB/s.)

ch_minio_s3 :) SHOW CREATE TABLE trips_s3 FORMAT Vertical

SHOW CREATE TABLE trips_s3
FORMAT Vertical

Query id: fa0571f7-e6b4-44aa-910a-9106d3e80a86

Row 1:
──────
statement: CREATE TABLE default.trips_s3
(
    `trip_id` UInt32,
    `pickup_date` Date,
    `pickup_datetime` DateTime,
    `dropoff_datetime` DateTime,
    `pickup_longitude` Float64,
    `pickup_latitude` Float64,
    `dropoff_longitude` Float64,
    `dropoff_latitude` Float64,
    `passenger_count` UInt8,
    `trip_distance` Float64,
    `tip_amount` Float32,
    `total_amount` Float32,
    `payment_type` Enum8('UNK' = 0, 'CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(pickup_date)
ORDER BY pickup_datetime
SETTINGS index_granularity = 8192, storage_policy = 's3_main'

1 row in set. Elapsed: 0.003 sec.
```
