# Processing JSON

Video: https://www.youtube.com/watch?v=gCg5ISOujtc

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Set the dataset as a parameter

```sql
SET param_url='https://storage.googleapis.com/clickhouse_public_datasets/pypi/sample/000000000000.json.gz';
```

[Ctrl+L]

Describe the dataset

```sql
DESCRIBE TABLE s3({url:String})
FORMAT TSV;
```

Describe the dataset without nullables

```sql
DESCRIBE (SELECT * FROM s3({url:String}))
SETTINGS schema_inference_make_columns_nullable = 0
FORMAT TSV;
```

Import data

```sql
CREATE TABLE pypi
ENGINE = MergeTree
ORDER BY (project, timestamp) AS
SELECT * FROM s3({url:String})
SETTINGS schema_inference_make_columns_nullable = 0;
```

Query data

```sql
SELECT project,  file.version, details.distro.name, count() AS c
FROM pypi
GROUP BY ALL
ORDER BY c DESC
LIMIT 5;
```