# Querying remote Parquet files

Video: https://www.youtube.com/watch?v=nnvtLLFy8fc

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Configure dataset location as a parameter

```sql
SET param_base='https://huggingface.co/datasets/vivym/midjourney-messages/resolve/main/data/';
```

View one row

```sql
FROM url({base:String} || '000000.parquet')
SELECT *
LIMIT 1
Format JSONEachRow
SETTINGS max_http_get_redirects=1;
```

Count the size of all images in one file

```sql
FROM url({base:String} || '000000.parquet')
SELECT sum(size) AS size, formatReadableSize(size) AS readable
SETTINGS max_http_get_redirects=1;
```


Count size of all images

```sql
FROM url({base:String} || '0000{00..55}.parquet')
SELECT sum(size) AS size, formatReadableSize(size) AS readable
SETTINGS max_http_get_redirects=1;
```

Compute average height and width too

```sql
FROM url({base:String} || '0000{00..55}.parquet')
SELECT sum(size) AS size, 
       formatReadableSize(size) AS readable,
       round(avg(width), 2) AS width, 
       round(avg(height), 2) AS height
SETTINGS max_http_get_redirects=1;
```