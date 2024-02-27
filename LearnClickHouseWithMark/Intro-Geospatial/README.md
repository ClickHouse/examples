# Intro to Geospatial

Video: https://www.youtube.com/watch?v=BKml8WUKb1c

List Speedtest by Ookla files

```bash
aws s3 ls \
  --no-sign-request \
  --recursive 's3://datasets-documentation/ookla/parquet'
```

Download files from Q3 and Q4 of 2023

```bash
aws s3 cp \
  --no-sign-request \
  's3://datasets-documentation/ookla/parquet/performance/type=mobile/year=2023/quarter=3/2023-07-01_performance_mobile_tiles.parquet' data
```

```bash
aws s3 cp \
  --no-sign-request \
  's3://datasets-documentation/ookla/parquet/performance/type=mobile/year=2023/quarter=4/2023-10-01_performance_mobile_tiles.parquet' data
```

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Setting to show compact output for the `DESCRIBE` clause

```sql
SET describe_compact_output=1;
```

Setting to not default column types to Nullable when ingesting files

```sql
SET schema_inference_make_columns_nullable=0;
```

Ingest data

```sql
CREATE TABLE performance
Engine = MergeTree
ORDER BY centroid
AS
FROM 'data/*.parquet'
SELECT 
  * EXCEPT('tile'),
  CAST((tile_x, tile_y) AS Point) AS centroid,
  CAST(readWKTPolygon(tile)[1] AS Ring) AS tile;
```

Compute average download and upload speed

```sql
FROM performance
select COLUMNS('avg_.*_kbps')
         APPLY(max)
         APPLY(x -> x/1000)
         APPLY(x -> round(x, 2)),
       COLUMNS('avg_.*_kbps')
         APPLY(avg)
         APPLY(x -> x/1000)
         APPLY(x -> round(x, 2))
FORMAT Vertical;
```

Compute average download and upload speed in London

```sql
SET param_london='POLYGON ((-0.516357 51.689585, -0.499878 51.460852, -0.450439 51.310013, 0.027466 51.258477, 0.192261 51.399206, 0.269165 51.532669, 0.142822 51.672555, -0.296631 51.720223, -0.516357 51.689585))';
```

```sql
FROM performance
select COLUMNS('avg_.*_kbps')
         APPLY(max)
         APPLY(x -> x/1000)
         APPLY(x -> round(x, 2)),
       COLUMNS('avg_.*_kbps')
         APPLY(avg)
         APPLY(x -> x/1000)
         APPLY(x -> round(x, 2))
WHERE pointInPolygon(centroid, readWKTPolygon({london:String}))
FORMAT Vertical;
```