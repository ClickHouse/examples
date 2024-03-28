# Aggregate Function Combinators

Video: https://youtu.be/Yku9mmBYm_4

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse -m
```

Download Parquet files from https://huggingface.co/datasets/vivym/midjourney-messages and put them into the `data` directory. 
Once you've done that, import the data into ClickHouse:

```sql
CREATE TABLE images
Engine = MergeTree
ORDER BY (size, height, width)
AS
SELECT * EXCEPT(content, url)
FROM file('data/0000{00..55}.parquet')
SETTINGS schema_inference_make_columns_nullable=0;
```

`count` and `countIf`

```sql
FROM images
SELECT count() FILTER(WHERE width >= 2000) AS bigCount,
       countIf(width >= 2000) AS bigCount;
```


```sql
FROM images
SELECT count() FILTER(WHERE width >= 2000) AS bigCount,
       countIf(width >= 2000) AS bigCount,
       countIf(width <= 340) AS smallCount,
       smallCount + bigCount AS bigSmallCount;
```

`countDistinct` and `countDistinctIf`

```sql
FROM images
SELECT countDistinct(width),
       countDistinct(height);
```


```sql
FROM images
SELECT countDistinct(width),
       countDistinct(height),
       countDistinctIf(width, channel_id = '989268300473192561') AS widthChannel,
       countDistinctIf(height, channel_id = '989268300473192561') AS heightChannel;
```

`avg` and `avgIf`

```sql
FROM images
SELECT avg(width),
       avg(height),
       avgIf(width, channel_id = '989268300473192561') AS widthChannel,
       avgIf(height, channel_id = '989268300473192561') AS heightChannel;
```


`avgIfOrNull` and `avgOrDefaultIf`


```sql
FROM images
SELECT avgIf(size, channel_id='foo') AS avgFoo,
       avgIfOrNull(size, channel_id='foo') AS avgFooNull,
       avgOrDefaultIf(size, channel_id='foo') AS avgFooDefault;
```

Resample functions


```sql
WITH (
    FROM images
    SELECT max(size) AS maxSize, formatReadableSize(maxSize)
) AS maxSize

FROM images
SELECT
    untuple(arrayJoin(arrayZip(
        countResample(0, maxSize, toUInt64(maxSize/10))(size),
        arrayMap(x -> formatReadableSize(x),
          minResample(0, maxSize, toUInt64(maxSize/10))(size, size)
        ),
        arrayMap(x -> formatReadableSize(x),
          maxResample(0, maxSize, toUInt64(maxSize/10))(size, size)
        ),
        avgResample(0, maxSize, toUInt64(maxSize/10))(width, size),
        avgResample(0, maxSize, toUInt64(maxSize/10))(height, size)
    ))) AS pair;
```

