# Greatest Common Denominator Codec

Video: https://www.youtube.com/watch?v=vaY5LQ7a_Dk

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Configure the Forex dataset as a parameter

```sql
SET param_url='https://datasets-documentation.s3.eu-west-3.amazonaws.com/forex/csv/year_month/*.csv.zst';
```

Query dataset

```sql
SELECT * FROM s3({url:String}, 'CSVWithNames')
LIMIT 1
FORMAT Vertical;
```

Create table

```sql
CREATE TABLE forex(
    `datetime` DateTime64(3),
    `base` LowCardinality(String),
    `quote` LowCardinality(String),
    `bid_v1` Decimal(76, 38) CODEC(ZSTD),
    `bid_v2` Decimal(76, 38) CODEC(GCD, ZSTD),
    `bid_v3` Decimal(11, 5) CODEC(ZSTD),
    `bid_v4` Decimal(11, 5) CODEC(GCD, ZSTD),
)
ENGINE = MergeTree
ORDER BY (base, quote, datetime);
```

Import data

```sql
INSERT INTO forex
SELECT datetime, base, quote, 
       bid AS bid_v1, bid AS bid_v2, 
       bid AS bid_v3, bid AS bid_v4
FROM s3({url:String}, 'CSVWithNames')
LIMIT 10_000_000
SETTINGS use_structure_from_insertion_table_in_table_functions=0;
```

Check column size

```sql
FROM system.columns
SELECT name,
       any(type) as type,
       any(compression_codec) AS codec,
       formatReadableSize(sum(data_compressed_bytes)) AS compressed,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed
WHERE table = 'forex' and name like 'bid%'
GROUP BY ALL;
```

Easier comparison

```sql
SELECT 
    type,
    formatReadableSize(
        sumIf(data_compressed_bytes, compression_codec LIKE '%GCD%')
    ) AS GCD,
    formatReadableSize(
        sumIf(data_compressed_bytes, compression_codec NOT LIKE '%GCD%')
    ) AS notGCD
FROM system.columns
WHERE (table = 'forex') AND (name LIKE 'bid%')
GROUP BY type;
```