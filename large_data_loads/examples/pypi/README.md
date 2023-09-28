# Example for resiliently loading a large data set

## Data set

The [PYPI dataset](https://clickhouse.com/blog/clickhouse-vs-snowflake-for-real-time-analytics-benchmarks-cost-analysis#pypi-dataset) is currently available as a [public table in BigQuery.](https://packaging.python.org/en/latest/guides/analyzing-pypi-package-downloads/#id10)  Each row in this dataset represents the download of a python package by a user e.g. using pip. 

We have exported this data as Parquet files, making it available in the public gcs bucket `https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample`. 

The aforementioned bucket contains a 3-month sample of the PyPi dataset consisting of ~70k files containing ~14 TB of uncompressed data.

## Step ①: Creating the empty target table, including one projection and two materialized views

### ClickHouse target table
```
CREATE TABLE pypi
(
    `timestamp` DateTime64(6),
    `date` Date MATERIALIZED timestamp,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String,
    `file` Tuple(filename String, project String, version String, type Enum8('bdist_wheel' = 0, 'sdist' = 1, 'bdist_egg' = 2, 'bdist_wininst' = 3, 'bdist_dumb' = 4, 'bdist_msi' = 5, 'bdist_rpm' = 6, 'bdist_dmg' = 7)),
    `installer` Tuple(name LowCardinality(String), version LowCardinality(String)),
    `python` LowCardinality(String),
    `implementation` Tuple(name LowCardinality(String), version LowCardinality(String)),
    `distro` Tuple(name LowCardinality(String), version LowCardinality(String), id LowCardinality(String), libc Tuple(lib Enum8('' = 0, 'glibc' = 1, 'libc' = 2), version LowCardinality(String))),
    `system` Tuple(name LowCardinality(String), release String),
    `cpu` LowCardinality(String),
    `openssl_version` LowCardinality(String),
    `setuptools_version` LowCardinality(String),
    `rustc_version` LowCardinality(String),
    `tls_protocol` Enum8('TLSv1.2' = 0, 'TLSv1.3' = 1),
    `tls_cipher` Enum8('ECDHE-RSA-AES128-GCM-SHA256' = 0, 'ECDHE-RSA-CHACHA20-POLY1305' = 1, 'ECDHE-RSA-AES128-SHA256' = 2, 'TLS_AES_256_GCM_SHA384' = 3, 'AES128-GCM-SHA256' = 4, 'TLS_AES_128_GCM_SHA256' = 5, 'ECDHE-RSA-AES256-GCM-SHA384' = 6, 'AES128-SHA' = 7, 'ECDHE-RSA-AES128-SHA' = 8)
)
Engine = MergeTree
ORDER BY (project, date, timestamp);
```

### Projection

Projection for speeding up the subquery:

```sql    
ALTER TABLE pypi
    ADD PROJECTION prj_count_by_project_system
    (
        SELECT
            project,
            system.1 AS system_name, -- doesn't work with system.name TODO: report to dev
            count() AS c
        GROUP BY
            project,
            system_name
    );
```

Query benefiting from the projection:
```sql 
SELECT
    system.1 as system
FROM pypi
WHERE system != ''
  AND project = 'boto3'
GROUP BY system
ORDER BY count () DESC LIMIT 10;
```

Query for checking if the projection is used:
```sql 
EXPLAIN indexes=1
SELECT
    system.1 as system
FROM pypi
WHERE system != ''
  AND project = 'boto3'
GROUP BY system
ORDER BY count () DESC LIMIT 10;


┌─explain────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Expression (Projection)                                                                                    │
│   Limit (preliminary LIMIT (without OFFSET))                                                               │
│     Sorting (Sorting for ORDER BY)                                                                         │
│       Expression (Before ORDER BY)                                                                         │
│         Aggregating                                                                                        │
│           Filter                                                                                           │
│             ReadFromMergeTree (prj_count_by_project_system)                                                │
│             Indexes:                                                                                       │
│               PrimaryKey                                                                                   │
│                 Keys:                                                                                      │
│                   project                                                                                  │
│                   tupleElement(system, 1)                                                                  │
│                 Condition: and((project in ['boto3', 'boto3']), (tupleElement(system, 1) not in ['', ''])) │
│                 Parts: 2/2                                                                                 │
│                 Granules: 2/212                                                                            │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```




### Materialized View 1

Target table for materialized view
```sql
CREATE TABLE pypi_downloads
(
    `project` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY project;
```

Materialized view

```sql
CREATE MATERIALIZED VIEW pypi_downloads_mv TO pypi_downloads
(
	`project` String,
	`count` Int64
) AS
SELECT
	project,
	count() AS count
FROM pypi
GROUP BY
	project;
```

Query benefiting from the mv:
```sql 
SELECT
	project,
	formatReadableQuantity(sum(count)) AS c
FROM pypi_downloads
GROUP BY project
ORDER BY c DESC
LIMIT 10;
```

### Materialized View 2

Target table for materialized view
```sql
CREATE TABLE pypi_countries
(
    `country_code` LowCardinality(String),
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY country_code;
```

Materialized view

```sql
CREATE MATERIALIZED VIEW pypi_countries_mv TO pypi_countries
(
	`country_code` LowCardinality(String),
	`count` Int64
) AS
SELECT
	country_code,
	count() AS count
FROM pypi
GROUP BY
	country_code;
```

Query benefiting from the mv:
```sql 
SELECT
	country_code,
	formatReadableQuantity(sum(count)) AS c
FROM pypi_countries
GROUP BY country_code
ORDER BY c DESC
LIMIT 10;
```


## Step ②: Use our script to resiliently load the data into the target table

This is the appropriate call of our script where we load the data into a [ClickHouse Cloud](https://clickhouse.com/cloud) service.
Note that each of the ~70k parquet files contains a bit less than 1 million rows. Therefore we configure the `rows_per_batch` setting to 1 million rows in order to load each file efficiently with a single load query.

Also, note that you need to adapt some settings, like `host`, `port`, `username`, and `password`.

```shell
python load_files.py \
--host f1e1rfvwho.us-central1.gcp.clickhouse-staging.com \
--port 8443 \
--username default \
--password XXX \
--url 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/*.parquet' \
--rows_per_batch 1000000 \
--database default \
--table pypi \
--cfg.format Parquet \
--cfg.structure  'timestamp DateTime64(6), country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String' \
--cfg.select "
    timestamp,
    country_code,
    url,
    project,
    (ifNull(file.filename, ''), ifNull(file.project, ''), ifNull(file.version, ''), ifNull(file.type, '')) AS file,
    (ifNull(installer.name, ''), ifNull(installer.version, '')) AS installer,
    python AS python,
    (ifNull(implementation.name, ''), ifNull(implementation.version, '')) AS implementation,
    (ifNull(distro.name, ''), ifNull(distro.version, ''), ifNull(distro.id, ''), (ifNull(distro.libc.lib, ''), ifNull(distro.libc.version, ''))) AS distro,
    (ifNull(system.name, ''), ifNull(system.release, '')) AS system,
    cpu AS cpu,
    openssl_version AS openssl_version,
    setuptools_version AS setuptools_version,
    rustc_version AS rustc_version,
    tls_protocol,
    tls_cipher" \
--cfg.query_settings input_format_null_as_default=1 input_format_parquet_import_nested=1 max_insert_threads=30
```
Note that all settings starting with `cfg.` are optional.

Also, note that we provide an increased `max_insert_threads` setting based on the size (Number of CPU cores and RAM) of our ClickHouse Cloud service. You need to adapt this to your used machine sizes.

## Step ③: Check that the projection and all materialized views have their data available

Run the queries mentioned above for this.
