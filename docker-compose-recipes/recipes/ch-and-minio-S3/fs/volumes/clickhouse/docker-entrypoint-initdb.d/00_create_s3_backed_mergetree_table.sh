
#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE trips_s3 ( trip_id UInt32, pickup_date Date, pickup_datetime DateTime, dropoff_datetime DateTime, pickup_longitude Float64, pickup_latitude Float64, dropoff_longitude Float64, dropoff_latitude Float64, passenger_count UInt8, trip_distance Float64, tip_amount Float32, total_amount Float32, payment_type Enum8( 'UNK' = 0, 'CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4 ) ) ENGINE = MergeTree PARTITION BY toYYYYMM(pickup_date) ORDER BY pickup_datetime SETTINGS index_granularity = 8192, storage_policy = 's3_main';
EOSQL
