## Scenario
- Two ClickHouse nodes
- Three ClickHouse Keeper nodes
- Database using the Replicated DB engine
- ReplicatedMergeTree table
- Storage on S3

## Configuration files
ClickHouse uses configuration files in `/etc/clickhouse-server/`.  During install
a file `config.xml` is added at `/etc/clickhouse-server/config.xml`, a file `users.xml` is added at `/etc/clickhouse-server/users.xml`, and two empty directories are also created:
- `/etc/clickhouse-server/config.d/`
- `/etc/clickhouse-server/users.d/`

All of your configuration should be added to those directories; config.xml and users.xml
in the parent directory should not be edited.

In the `docker-compose.yaml` file you will see that there are configuration files 
mounted from the `fs/volumes/` directories into the containers, and when you start
things up you will see log messages telling you that the configuration in those mounted
files is merged with the default configuration.

You should have a look at the configuration files in `fs/volumes/` to understand how
- S3 storage is added as a disk
- that local storage is used as a cache
- experimental settings are enabled
- etc.

## Create Object Storage (S3, GCS, MinIO, etc.)
Using S3 as an example, create a bucket and assign a key / secret that can manage
the bucket and objects.  Put the details in the file `s3-variables.env` in the same
directory as the `docker-compose.yaml` file.

In this example, the bucket is `my-clickhouse-s3-disk` and the folder is `data`

If you need more info on creating the bucket and assigning an access key, see
[Use S3 Object Storage as a ClickHouse disk](https://clickhouse.com/docs/en/integrations/s3#configuring-s3-for-clickhouse-use)

```
ENDPOINT=https://my-clickhouse-s3-disk.s3.amazonaws.com/data/
ACCESS_KEY_ID=AKIABBBBBBBBBBBBBBBB
SECRET_ACCESS_KEY=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
```

## Start the containers
```bash
docker compose up
```

Note: Recent versions of Docker include `docker compose`, if `docker compose` does not exist
on your system you may need to install a Python based `docker-compose` and add the `-` to
your commands.

## Database DDL on clickhouse-01

```bash
docker compose exec clickhouse-01 clickhouse-client
```

```sql
CREATE DATABASE ReplicatedDB
ENGINE = Replicated('/test/ReplicatedDB', 'shard1', concat('replica', '1'))
```

## Database DDL on clickhouse-02

```bash
docker compose exec clickhouse-02 clickhouse-client
```

```sql
CREATE DATABASE ReplicatedDB
ENGINE = Replicated('/test/ReplicatedDB', 'shard1', 'replica2')
```

## Table DDL on clickhouse-01

This table DDL adds a `SETTINGS` line and specifies the storage policy `s3_main`
(see `storage.xml`).

```sql
CREATE TABLE ReplicatedDB.uk_price_paid
(
    price UInt32,
    date Date,
    postcode1 LowCardinality(String),
    postcode2 LowCardinality(String),
    type Enum8('terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4, 'other' = 0),
    is_new UInt8,
    duration Enum8('freehold' = 1, 'leasehold' = 2, 'unknown' = 0),
    addr1 String,
    addr2 String,
    street LowCardinality(String),
    locality LowCardinality(String),
    town LowCardinality(String),
    district LowCardinality(String),
    county LowCardinality(String)
)
ENGINE = ReplicatedMergeTree
ORDER BY (postcode1, postcode2, addr1, addr2)
SETTINGS storage_policy='s3_main';
```
```response
Query id: 60e09cd7-c3bd-4769-8708-3116a3e0fdc7

┌─shard──┬─replica──┬─status─┬─num_hosts_remaining─┬─num_hosts_active─┐
│ shard1 │ replica1 │ OK     │                   1 │                1 │
└────────┴──────────┴────────┴─────────────────────┴──────────────────┘
┌─shard──┬─replica──┬─status─┬─num_hosts_remaining─┬─num_hosts_active─┐
│ shard1 │ replica2 │ OK     │                   0 │                0 │
└────────┴──────────┴────────┴─────────────────────┴──────────────────┘

2 rows in set. Elapsed: 0.101 sec.
```

Note: The response to the DDL to create the table shows that the table was created on
both replicas (clickhouse-01, and clickhouse-02)

## Look at the storage policy details

Query `system.tables` and note that the storage_policy is `s3_main`:

```sql
SELECT
    name,
    engine,
    data_paths,
    metadata_path,
    storage_policy,
    formatReadableSize(total_bytes)
FROM system.tables
WHERE name = 'uk_price_paid'
FORMAT Vertical
```
```response
Row 1:
──────
name:                            uk_price_paid
engine:                          ReplicatedMergeTree
data_paths:                      ['/var/lib/clickhouse/disks/s3_disk/store/0ae/0ae2b58b-b6af-4b2b-bc2f-325b57cf8629/']
metadata_path:                   /var/lib/clickhouse/store/9fd/9fd691d3-65b0-4a94-bcc4-d2823849cd8e/uk_price_paid.sql
storage_policy:                  s3_main
formatReadableSize(total_bytes): 0.00 B
```

## Insert data on clickhouse-01
```sql
INSERT INTO ReplicatedDB.uk_price_paid
WITH
   splitByChar(' ', postcode) AS p
SELECT
    toUInt32(price_string) AS price,
    parseDateTimeBestEffortUS(time) AS date,
    p[1] AS postcode1,
    p[2] AS postcode2,
    transform(a, ['T', 'S', 'D', 'F', 'O'], ['terraced', 'semi-detached', 'detached', 'flat', 'other']) AS type,
    b = 'Y' AS is_new,
    transform(c, ['F', 'L', 'U'], ['freehold', 'leasehold', 'unknown']) AS duration,
    addr1,
    addr2,
    street,
    locality,
    town,
    district,
    county
FROM url(
    'http://prod.publicdata.landregistry.gov.uk.s3-website-eu-west-1.amazonaws.com/pp-complete.csv',
    'CSV',
    'uuid_string String,
    price_string String,
    time String,
    postcode String,
    a String,
    b String,
    c String,
    addr1 String,
    addr2 String,
    street String,
    locality String,
    town String,
    district String,
    county String,
    d String,
    e String'
) SETTINGS max_http_get_redirects=10;
```

Note: Information about the dataset can be found here:
- Source: https://www.gov.uk/government/statistical-data-sets/price-paid-data-downloads
- Description of the fields: https://www.gov.uk/guidance/about-the-price-paid-data
- Contains HM Land Registry data © Crown copyright and database right 2021. This data is licensed under the Open Government Licence v3.0.


## Query the table on the second replica
The loading time is dependent on your connection speed, once you see that data is loading on one of the nodes you can query it on the other node.  If there are zero rows wait a few seconds and try again, the data has to be downloaded to your workstation and then written to S3.

```sql
SELECT town
FROM ReplicatedDB.uk_price_paid
LIMIT 100
```
```response
┌─town───────────────┐
│ PERRANPORTH        │
│ BRIXHAM            │
│ CALLINGTON         │
│ HITCHIN            │
│ BURY ST. EDMUNDS   │
│ DARTFORD           │
│ BURNLEY            │
.
.
.
```

## More queries
The UK Price Paid dataset has a dedicated page in the ClickHouse documentation.  See
[Example Dataset: UK Price Paid](https://clickhouse.com/docs/en/getting-started/example-datasets/uk-price-paid) for some interesting queries.

