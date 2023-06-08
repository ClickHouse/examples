## Scenario
- Three ClickHouse nodes
- Three ClickHouse Keeper nodes
- Database using the Replicated DB engine
- ReplicatedMergeTree table

## Questions
- Can I use S3 for the disk?
- Can I make one node read/write and others read only (compute nodes that do not write to the source tables in S3)?
- Can I add a node without restarting the original nodes?

## Start the containers
```bash
docker compose up
```

Note: On recent versions of Docker `docker compose` is included, if `docker compose` does not work
on your system you may need to install a Python based `docker-compose` and add the `-` to your
commands.

## Database DDL on main node

```bash
docker compose exec clickhouse-01 clickhouse-client
```

```sql
CREATE DATABASE ReplicatedDB ENGINE = Replicated('/test/ReplicatedDB', 'shard1', 'replica' || '1');
```

```sql

```

## Database DDL on second node

```bash
docker compose exec clickhouse-02 clickhouse-client
```

```sql
CREATE DATABASE ReplicatedDB ENGINE = Replicated('/test/ReplicatedDB', 'shard1', 'replica2');
```

## Table DDL on main node

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
ORDER BY (postcode1, postcode2, addr1, addr2);
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


## Insert data on main node
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

## Query the table on the second replica
While the data is streaming into the table on the main node (clickhouse-01) query it on
the second:
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

## Question: What happens?
I had to create the replicated database on both nodes, but the DDL for the table was done once, and propogated to the second node.  The data also was inserted to both nodes without doing anything secial (just using the ReplicatedMergeTree table engine.


## Use S3
Storage Policy is `s3_main` (see `storage.xml`).  To create the above table on S3:

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
ORDER BY (postcode1, postcode2, addr1, addr2);
# highlight-next-line
SETTINGS storage_policy='s3_main'
```
