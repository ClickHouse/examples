## Shortest Path between two traces

Originally from [Awesome BigQuery Views](https://github.com/blockchain-etl/awesome-bigquery-views/blob/master/ethereum/shortest-path-via-traces.sql).

## BigQuery


```sql
# This query will fail if there are too many traces. 
# There is a workaround here:
# https://console.cloud.google.com/bigquery?sq=749871510730:082d50190dc04d79aaf7ee4d5c6f9d00

DECLARE start_address STRING DEFAULT LOWER('0x47068105c5feff69e44520b251b9666d4b512a70');
DECLARE end_address STRING DEFAULT LOWER('0x2604afb5a64992e5abbf25865c9d3387ade92bad');

WITH traces_0 AS (
  SELECT *
  FROM `bigquery-public-data.crypto_ethereum.traces`
  WHERE from_address = start_address
),
traces_1_hop AS (
  SELECT
      1 AS hops,
      traces_1.from_address,
      traces_1.to_address,
      traces_1.trace_address,
      traces_1.block_timestamp,
      concat(traces_0.from_address, ' -> ', traces_0.to_address, ' -> ', traces_1.to_address) as path
  FROM `bigquery-public-data.crypto_ethereum.traces` AS traces_1
  INNER JOIN traces_0
  ON traces_0.to_address = traces_1.from_address
  AND traces_0.block_timestamp <= traces_1.block_timestamp 
),
traces_2_hops AS (
  SELECT
      2 AS hops,
      traces_2.from_address,
      traces_2.to_address,
      traces_2.trace_address,
      traces_2.block_timestamp,
      concat(path, ' -> ', traces_2.to_address) AS path
  FROM `bigquery-public-data.crypto_ethereum.traces` AS traces_2
  INNER JOIN traces_1_hop
  ON traces_1_hop.to_address = traces_2.from_address
  AND traces_1_hop.block_timestamp <= traces_2.block_timestamp 
),
traces_3_hops AS (
  SELECT
      3 AS hops,
      traces_3.from_address,
      traces_3.to_address,
      traces_3.trace_address,
      traces_2_hops.block_timestamp,
      concat(path, ' -> ', traces_3.to_address) AS path
  FROM `bigquery-public-data.crypto_ethereum.traces` AS traces_3
  INNER JOIN traces_2_hops
  ON traces_2_hops.to_address = traces_3.from_address
  AND traces_2_hops.block_timestamp <= traces_3.block_timestamp 
  WHERE traces_3.to_address = end_address
),
traces_all_hops AS (
    SELECT * FROM traces_1_hop
    UNION ALL
    SELECT * FROM traces_2_hops
    UNION ALL
    SELECT * FROM traces_3_hops
)
SELECT *
FROM traces_all_hops
WHERE hops = 3
LIMIT 100
```



## ClickHouse

TODO