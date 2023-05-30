# Debezium for CDC with Postgres and ClickHouse

For our example we use the uk house price paid dataset of 28m rows. Examples below will need to be adjusted based on your schema.

## Requirements

- Kafka
- Postgres 10+ - tested on version 14.7 using `pgoutput`
- Debezium Connector - tested on version 2.2.1
- [ClickHouse Sink for Kafka](https://clickhouse.com/docs/en/integrations/kafka#clickhouse-kafka-connect-sink) or [HTTP Sink](https://clickhouse.com/docs/en/integrations/kafka#confluent-http-sink-connector) (Confluent Cloud only)

These examples use a AWS Aurora instance of Postgres version X. We use Confluent for hosting our Kafka instance and connectors but self-managed variants should also work.

## Pre-loading data into Postgres

UK house price data in postgres insert format can be found [here](https://datasets-documentation.s3.eu-west-3.amazonaws.com/uk-house-prices/postgres/uk_prices.sql.tar.gz).

Create your Postgres table as shown below:

```sql
CREATE TABLE uk_price_paid                                                                                                                                                                   (
   id serial primary key,
   price INTEGER,
   date Date,
   postcode1 varchar(8),
   postcode2 varchar(3),
   type varchar(13),
   is_new SMALLINT,
   duration varchar(9),
   addr1 varchar(100),
   addr2 varchar(100),
   street varchar(60),
   locality varchar(35),
   town varchar(35),
   district varchar(40),
   county varchar(35)
);
```

Download the data

```bash
wget https://datasets-documentation.s3.eu-west-3.amazonaws.com/uk-house-prices/postgres/uk_prices.sql.tar.gz
tar -xvf uk_prices.sql.tar.gz
```

Insert the data using psql.

```bash
PGPASSWORD=<password>
PGUSER=postgres
PGHOST=<host>

psql < house_prices.sql
```

Confirm all data has been loaded. This can take 10 mins.

```sql
postgres=> SELECT count(*) FROM uk_price_paid;
  count
----------
 27734966
(1 row)
```

## Configure Postgres

The PostgreSQL connector can be used with a standalone PostgreSQL server or with a cluster of PostgreSQL servers. It relies on the PostgreSQL logical decoding feature that allows clients to extract all persistent changes to database tables into a coherent format. This is supported on primary servers only - the Debezium connector can therefore not connect to a replica instance.

Ensure the Postgres instance is appropriately configured:

- Self-managed configurations details [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-server-configuration)
- For Cloud-based environments e.g. Amazon RDS see [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-in-the-cloud)

Note: An output plugin transforms the data from the write-ahead log’s internal representation into a format the consumer of a replication slot needs. Our examples below use logical replication stream mode `pgoutput`. This is built into PostgreSQL 10+. Earlier versions can utilize [decoderbufs](https://github.com/debezium/postgres-decoderbufs) which is maintained by the Debezium community or [wal2json](https://github.com/eulerto/wal2json/blob/master/README.md). We have not tested this configuration.

**Our examples use Amazon RDS PostgreSQL instance**

We recommend users read the following sections regarding security and configuration of users:

 - [Setting up basic permissions](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-permissions) - For our example below, we utilize the `postgres` super user. This is not advised for production deployments.
 - [Privileges  to create Publications](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-replication-user-privileges) - Debezium streams change events for PostgreSQL source tables from publications that are created for the tables. Publications contain a filtered set of change events that are generated from one or more tables. The data in each publication is filtered based on the publication specification. We assume Debezium is configured with sufficient permission to create these publications. By default, the `postgres` super user has permission for this operation. For production use cases, however, we recommend users create these publications themselves or [minimize the permissions](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-replication-user-privileges) of the Debezium user assigned to the connector used to create them.
 - [Permissions to allow replication with the Debenzium connector host](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-host-replication-permissions)

### Configuring tables

REPLICA IDENTITY is a PostgreSQL-specific table-level setting that determines the amount of information that is available to the logical decoding plug-in for UPDATE and DELETE events.  More specifically, the setting of REPLICA IDENTITY controls what (if any) information is available for the previous values of the table columns involved, whenever an UPDATE or DELETE event occurs.

While 4 different values are supported, we recommend the following based on whether you need support for deletes:

- `DEFAULT` - The default behavior is that UPDATE and DELETE events contain the previous values for the primary key columns of a table if that table has a primary key. For an UPDATE event, only the primary key columns with changed values are present. If a table does not have a primary key, the connector does not emit UPDATE or DELETE events for that table. Only use this value if: 
    - Your ClickHouse `ORDER BY` clause only contains the Postgres primary key columns. This is unlikely since typically users add columns to the `ORDER BY` to optimize aggregation queries, that are unlikely to be primary keys in Postgres.
    - You do no need support for deletes. Note: The pipeline used below does not need the previous column values for updates. The are required for deletes as the `after` state is null.
- `FULL` - Emitted events for UPDATE and DELETE operations contain the previous values of all columns in the table. This is needed if you need to support delete operations.

Set this setting using the `ALTER` command.

```sql
ALTER TABLE uk_price_paid REPLICA IDENTITY FULL;
```

## Prepare ClickHouse

For ClickHouse we use a [`ReplacingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree). Create the schema as follows:

```sql
CREATE TABLE default.uk_price_paid
(
    `id` UInt64,
    `price` UInt32,
    `date` Date,
    `postcode1` LowCardinality(String),
    `postcode2` LowCardinality(String),
    `type` Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4),
    `is_new` UInt8,
    `duration` Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2),
    `addr1` String,
    `addr2` String,
    `street` LowCardinality(String),
    `locality` LowCardinality(String),
    `town` LowCardinality(String),
    `district` LowCardinality(String),
    `county` LowCardinality(String),
    `version` UInt64,
    `deleted` UInt8
)
ENGINE = ReplacingMergeTree(version, deleted) ORDER BY (postcode1, postcode2, addr1, addr2, id)
```

Note the use of the `version` and `deleted` fields. The former is used to identify the latest version of a row, only returning this in search results. Later versions of a row must contain a higher value - this can be arbitarily higher. The latter column `deleted` contains the values `0` or `1`, where `1` indicates if a row has been removed. **This column, and the configuration parameter, can be ommitted if delete support is not required**. The `id` field is the primary key of the rows in Postgres.

For example, suppose the following row exists in the table (columns removed for brevity):

```json
{"id":"12304389","price":149950,"date":"2007-06-29","postcode1":"B10","postcode2":"0LJ","type":"semi-detached","is_new":0,"duration":"freehold",
"addr1":"26","addr2":"","street":"GOLDEN HILLOCK ROAD","locality":"SMALL HEATH","town":"BIRMINGHAM","district":"BIRMINGHAM","county":"WEST MIDLANDS",
"version":1,"deleted":0}
```

To update the price of this row to `249950`, the following row must be sent by ClickHouse:

```json
{"id":"12304389","price":249950,"date":"2007-06-29","postcode1":"B10","postcode2":"0LJ","type":"semi-detached","is_new":0,"duration":"freehold",
"addr1":"26","addr2":"","street":"GOLDEN HILLOCK ROAD","locality":"SMALL HEATH","town":"BIRMINGHAM","district":"BIRMINGHAM","county":"WEST MIDLANDS",
"version":2,"deleted":0}
```

To delete the row, the following must be sent:

```json
{"id":"12304389","price":249950,"date":"2007-06-29","postcode1":"B10","postcode2":"0LJ","type":"semi-detached","is_new":0,"duration":"freehold",
"addr1":"26","addr2":"","street":"GOLDEN HILLOCK ROAD","locality":"SMALL HEATH","town":"BIRMINGHAM","district":"BIRMINGHAM","county":"WEST MIDLANDS",
"version":3,"deleted":1}
```

Adding a new row simply requires values which are unique for our `ORDER BY` columns. The ReplacingMergeTree will reconcile these updates/delete at query time, utilizing only the latest version of a row.

**Important** - The ReplacingMergeTree uses the `ORDER BY` columns to identify rows belonging to the same Postgres row. These values must be immutable and not change in Postgres - they are effectively a unique identifier. Select these accordingly whilst also optimizing for ClickHouse access patterns and search performance - see [A Practical Introduction to Primary Indexes in ClickHouse](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes) for further details. This `ORDER BY` will nearly always contain the Postgres primary key, for identification purposes. This is unlikely to be useful for searches so should always be appended to the end of the `ORDER BY` as shown - see [here](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes#ordering-key-columns-efficiently) for reasoning.

Changes will not be sent by Debezium in the following format. To transform Debezium messages to the appropriate above format, we utilize a materialized view.

## Debezium Messages

[Debezimum consumes the Postgres WAL]() to identify changes. Based on whether a create, update or delete operation is created a different message will be sent to Kafka. 

The Debezimum connector produces a change event for every row-level insert, update, and delete operation that was captured and sends change event records for each table in a separate Kafka topic.

The content of these messages depends on whether you configure `REPLICA IDENTITY`. If set, messages will include the state of the changed row `before` AND `after` the change. If not set, only the final state of the row will be sent to ClickHouse. To support deletes, `REPLICA IDENTITY` must be configured as `FULL` rathert than `DEFAULT`. We show both message formats below. The following assumes the user has configured the setting `After-state only` as `false` if using Confluent Cloud's hosted connector.

Note how the `op` column denotes the operation type i.e. `d` for delete, `u` for update, `c` for create.

### Create messages

#### `REPLICA IDENTITY=DEFAULT`

```json
{
  "before": null,
  "after": {
    "id": 55507462,
    "price": 247500,
    "date": 13693,
    "postcode1": "MK12",
    "postcode2": "5GY",
    "type": "semi-detached",
    "is_new": 0,
    "duration": "freehold",
    "addr1": "35",
    "addr2": "",
    "street": "TURNEYS DRIVE",
    "locality": "WOLVERTON MILL",
    "town": "MILTON KEYNES",
    "district": "MILTON KEYNES",
    "county": "MILTON KEYNES"
  },
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685379350955,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247967255240\",\"247967257096\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106955,
    "lsn": 247967257096,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1685379351723,
  "transaction": null
}
```

#### `REPLICA IDENTITY=FULL`

```json
{
  "before": null,
  "after": {
    "id": 55507461,
    "price": 120000,
    "date": 10760,
    "postcode1": "SG5",
    "postcode2": "4JZ",
    "type": "detached",
    "is_new": 0,
    "duration": "freehold",
    "addr1": "30",
    "addr2": "",
    "street": "HAZEL GROVE",
    "locality": "STOTFOLD",
    "town": "HITCHIN",
    "district": "MID BEDFORDSHIRE",
    "county": "BEDFORDSHIRE"
  },
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685378749598,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247430390416\",\"247833035832\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106939,
    "lsn": 247833035832,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1685378750345,
  "transaction": null
}
```

### Update messages

#### `REPLICA IDENTITY=DEFAULT`

```json
{
  "before": null,
  "after": {
    "id": 41794967,
    "price": 205000,
    "date": 15932,
    "postcode1": "PO13",
    "postcode2": "9BH",
    "type": "detached",
    "is_new": 1,
    "duration": "freehold",
    "addr1": "9",
    "addr2": "",
    "street": "CHESTER CRESCENT",
    "locality": "",
    "town": "LEE-ON-THE-SOLENT",
    "district": "GOSPORT",
    "county": "HAMPSHIRE"
  },
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685379446120,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247967259768\",\"247967261784\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106958,
    "lsn": 247967261784,
    "xmin": null
  },
  "op": "u",
  "ts_ms": 1685379446255,
  "transaction": null
}
```

#### `REPLICA IDENTITY=FULL`

```json
{
  "before": {
    "id": 50658675,
    "price": 227500,
    "date": 11905,
    "postcode1": "SP2",
    "postcode2": "7EN",
    "type": "detached",
    "is_new": 0,
    "duration": "freehold",
    "addr1": "31",
    "addr2": "",
    "street": "CHRISTIE MILLER ROAD",
    "locality": "SALISBURY",
    "town": "SALISBURY",
    "district": "SALISBURY",
    "county": "WILTSHIRE"
  },
  "after": {
    "id": 50658675,
    "price": 227500,
    "date": 11905,
    "postcode1": "SP2",
    "postcode2": "7EN",
    "type": "terraced",
    "is_new": 0,
    "duration": "freehold",
    "addr1": "31",
    "addr2": "",
    "street": "CHRISTIE MILLER ROAD",
    "locality": "SALISBURY",
    "town": "SALISBURY",
    "district": "SALISBURY",
    "county": "WILTSHIRE"
  },
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685378780355,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247833040488\",\"247833042536\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106940,
    "lsn": 247833042536,
    "xmin": null
  },
  "op": "u",
  "ts_ms": 1685378780514,
  "transaction": null
}
```


### Delete messages

#### `REPLICA IDENTITY=DEFAULT`

```json
{
  "before": {
    "id": 50419765,
    "price": null,
    "date": null,
    "postcode1": null,
    "postcode2": null,
    "type": null,
    "is_new": null,
    "duration": null,
    "addr1": null,
    "addr2": null,
    "street": null,
    "locality": null,
    "town": null,
    "district": null,
    "county": null
  },
  "after": null,
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685379500528,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247967265912\",\"247967265968\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106959,
    "lsn": 247967265968,
    "xmin": null
  },
  "op": "d",
  "ts_ms": 1685379500562,
  "transaction": null
}
```

Deletes will not be supported for these messages.

#### `REPLICA IDENTITY=FULL`

```json
{
  "before": {
    "id": 43637598,
    "price": 581500,
    "date": 17799,
    "postcode1": "NW1",
    "postcode2": "3PR",
    "type": "flat",
    "is_new": 0,
    "duration": "leasehold",
    "addr1": "29",
    "addr2": "",
    "street": "MUNSTER SQUARE",
    "locality": "",
    "town": "LONDON",
    "district": "CAMDEN",
    "county": "GREATER LONDON"
  },
  "after": null,
  "source": {
    "version": "1.9.6.Final",
    "connector": "postgresql",
    "name": "postgres_server",
    "ts_ms": 1685378804044,
    "snapshot": "false",
    "db": "postgres",
    "sequence": "[\"247833046808\",\"247833046912\"]",
    "schema": "public",
    "table": "uk_price_paid",
    "txId": 106942,
    "lsn": 247833046912,
    "xmin": null
  },
  "op": "d",
  "ts_ms": 1685378804649,
  "transaction": null
}
```

### Persisting messages

These change messages will be sent to a table `uk_price_paid_changes` in ClickHouse. This table will have a [materialized view]() configured which [will trigger]() on inserts, sending the transformed rows to our `uk_price_paid` table in the appropriate format. The following schema assumes `REPLICA IDENTITY` is configured as `FULL` as deletes are required.

```sql
CREATE TABLE uk_price_paid_changes
(
    `before.id` Nullable(UInt64),
    `before.price` Nullable(UInt32),
    `before.date` Nullable(UInt32),
    `before.postcode1` Nullable(String),
    `before.postcode2` Nullable(String),
    `before.type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `before.is_new` Nullable(UInt8),
    `before.duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `before.addr1` Nullable(String),
    `before.addr2` Nullable(String),
    `before.street` Nullable(String),
    `before.locality` Nullable(String),
    `before.town` Nullable(String),
    `before.district` Nullable(String),
    `before.county` Nullable(String),
    `after.id` Nullable(UInt64),
    `after.price` Nullable(UInt32),
    `after.date` Nullable(UInt32),
    `after.postcode1` Nullable(String),
    `after.postcode2` Nullable(String),
    `after.type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `after.is_new` Nullable(UInt8),
    `after.duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `after.addr1` Nullable(String),
    `after.addr2` Nullable(String),
    `after.street` Nullable(String),
    `after.locality` Nullable(String),
    `after.town` Nullable(String),
    `after.district` Nullable(String),
    `after.county` Nullable(String),
    `op` LowCardinality(String),
    `ts_ms` UInt64,
    `source.sequence` String,
    `source.lsn` UInt64
)
ENGINE = MergeTree
ORDER BY tuple()
```

For debugging purposes we are using a `MergeTree` engine for this table. In production scenarios, this could be `Null` engine - changes will then not be persisted, but transformed rows still sent to the target table `uk_price_paid`.

If delete support is not required, and `REPLICA IDENTITY` is set to `DEFAULT`, the simpler table can be used.

```sql
CREATE TABLE uk_price_paid_changes
(
    `after.id` Nullable(UInt64),
    `after.price` Nullable(UInt32),
    `after.date` Nullable(UInt32),
    `after.postcode1` Nullable(String),
    `after.postcode2` Nullable(String),
    `after.type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `after.is_new` Nullable(UInt8),
    `after.duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `after.addr1` Nullable(String),
    `after.addr2` Nullable(String),
    `after.street` Nullable(String),
    `after.locality` Nullable(String),
    `after.town` Nullable(String),
    `after.district` Nullable(String),
    `after.county` Nullable(String),
    `op` LowCardinality(String),
    `ts_ms` UInt64,
    `source.sequence` String,
    `source.lsn` UInt64
)
ENGINE = MergeTree
ORDER BY tuple()
```

Note: An astute reader will notice our schema is flattened from the nested messages sent by Debezium. We will do this in our Debezium connector. This is a simpler form a schema perspective and allows us to configure the `Nullable` values. Alternatives involving `Tuple` are more complex. You may also notice we support the `op` type `r`. Messages of this type represent the initial state of the Postgres table. Debezium sends these if configured to snapshot the table state on starting. Fortunately, these messages are indistinguisable from create messages.

## Prepare Materialized view

We utilize a materialized view to transform Debezium messages into the format noted above.

The required materialized view will depend on whether `REPLICA IDENTITY` is configured as `FULL` and whether delete support is required. Select the appropriate view accordingly.

### Delete support view

Notice our materialized view here selects the appropriate value for each column depending on the operation. The `version` is based on the `source.lsn` column from the WAL log which which is [guaranteed to be higher](https://www.postgresql.org/docs/current/wal-internals.html). We also set the `deleted` column to 1, if the `op` column has a `d` value, and 0 otherwise.

```sql
CREATE MATERIALIZED VIEW default.uk_price_paid_mv TO default.uk_price_paid
(
    `id` Nullable(UInt64),
    `price` Nullable(UInt32),
    `date` Nullable(Date),
    `postcode1` Nullable(String),
    `postcode2` Nullable(String),
    `type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `is_new` Nullable(UInt8),
    `duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `addr1` Nullable(String),
    `addr2` Nullable(String),
    `street` Nullable(String),
    `locality` Nullable(String),
    `town` Nullable(String),
    `district` Nullable(String),
    `county` Nullable(String),
    `version` UInt64,
    `deleted` UInt8
) AS
SELECT
    if(op = 'd', before.id, after.id) AS id,
    if(op = 'd', before.price, after.price) AS price,
    if(op = 'd', toDate(before.date), toDate(after.date)) AS date,
    if(op = 'd', before.postcode1, after.postcode1) AS postcode1,
    if(op = 'd', before.postcode2, after.postcode2) AS postcode2,
    if(op = 'd', before.type, after.type) AS type,
    if(op = 'd', before.is_new, after.is_new) AS is_new,
    if(op = 'd', before.duration, after.duration) AS duration,
    if(op = 'd', before.addr1, after.addr1) AS addr1,
    if(op = 'd', before.addr2, after.addr2) AS addr2,
    if(op = 'd', before.street, after.street) AS street,
    if(op = 'd', before.locality, after.locality) AS locality,
    if(op = 'd', before.town, after.town) AS town,
    if(op = 'd', before.district, after.district) AS district,
    if(op = 'd', before.county, after.county) AS county,
    if(op = 'd', source.lsn, source.lsn) AS version,
    if(op = 'd', 1, 0) AS deleted
FROM default.uk_price_paid_changes
WHERE (op = 'c') OR (op = 'r') OR (op = 'u') OR (op = 'd')
```

### Only creates and deletes

If only creates and updates need to be supported our materialized view is simpler as only the final state of the row is recieved from Debezium. Below we simply set the `deleted` and `version` columns.

```sql
CREATE MATERIALIZED VIEW default.uk_price_paid_mv TO default.uk_price_paid
(
    `id` Nullable(UInt64),
    `price` Nullable(UInt32),
    `date` Nullable(Date),
    `postcode1` Nullable(String),
    `postcode2` Nullable(String),
    `type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `is_new` Nullable(UInt8),
    `duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `addr1` Nullable(String),
    `addr2` Nullable(String),
    `street` Nullable(String),
    `locality` Nullable(String),
    `town` Nullable(String),
    `district` Nullable(String),
    `county` Nullable(String),
    `version` UInt64,
    `deleted` UInt8
) AS
SELECT
    after.id AS id,
    after.price AS price,
    toDate(after.date) AS date,
    after.postcode1 AS postcode1,
    after.postcode2 AS postcode2,
    after.type AS type,
    after.is_new AS is_new,
    after.duration AS duration,
    after.addr1 AS addr1,
    after.addr2 AS addr2,
    after.street AS street,
    after.locality AS locality,
    after.town AS town,
    after.district AS district,
    after.county AS county,
    source.lsn AS version
FROM uk_price_paid_changes
WHERE (op = 'c') OR (op = 'r') OR (op = 'u')
```

## Load ClickHouse Data

To load the initial data into ClickHouse we can either:

- Rely on Debezium to send the initial state (typically slower)
- Pause changes to our Postgres table and insert the rows to our ClickHouse table using the [`postgres`]()table function. This can be achieved using an `INSERT INTO SELECT` query as shown below. This approach is typically faster.

```sql
INSERT INTO uk_price_paid SELECT id, price, date, postcode1, postcode2, type, is_new, duration, addr1, addr2, street, locality, town, district, county, 1 AS version, 0 AS deleted
FROM postgresql('<host>', '<database>', '<table>', '<user>', '<password>')
```

The `deleted` column here can be ommitted if deletes are not being supported. Once complete, confirm the count is identical to Postgres.

```sql
SELECT count()
FROM uk_price_paid

┌──count()─┐
│ 27740666 │
└──────────┘
```

## Configure Kafka


We assume users will deploy Debezium using the Apache Kafka Connect framework and utilize the [recommended architecture](https://debezium.io/documentation/reference/stable/architecture.html). [Debezium Server](https://debezium.io/documentation/reference/stable/architecture.html#_debezium_server) architectures will likely work but are not tested.

In our example below we assume the user is using Confluent Cloud for the hosting of Kafka. However, self-managed Kafka installations are supported. Debezium uses (either via Kafka Connect or directly) multiple topics for storing data. Instructions for installating Debezium, and considerations for the topic configuration, can be found [here](https://debezium.io/documentation/reference/stable/install.html).

The solution proposed below supports out of order events. Users can therefore safely configure multiple partition topics and use multiple connector tasks to consume messages sent by Debezium - although this should be rarely needed for most throughputs.


### Topic Naming

By default, the Debezium connector writes events that occur in a table to a single Apache Kafka topic that is specific to that table.  This uses the [naming convenion](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-topic-names) `topicPrefix.schemaName.tableName` where `topicPrefix` can be configured via the parameter `topic.prefix`. In our example, we utilize the [Single Message Transformation (SMT)](https://debezium.io/documentation/reference/stable/transformations/topic-routing.html#topic-routing) capabiliies of Kakfa Connect to set the topic name explictly.

We assume users have either created their topic or are using Auto Topic Creation - further details [here](https://docs.confluent.io/kafka-connectors/debezium-postgres-source/current/postgres_source_connector_config.html#auto-topic-creation) and [here](https://docs.confluent.io/platform/current/connect/userguide.html#connect-source-auto-topic-creation). Pre-created topics should be configured to receieve schema-less JSON.

## Configure Debezium

Deploying the connector in the Kafka connect framework requires the following settings. Note how we assume messages are sent as [JSON with no schema registry](https://docs.confluent.io/platform/current/connect/userguide.html#json-without-sr):

- `value.converter` - `org.apache.kafka.connect.json.JsonConverter`
- `key.converter` - `org.apache.kafka.connect.storage.StringConverter`
- `key.converter.schemas.enable` - `false`
- `value.converter.schemas.enable` - `false`
- `decimal.format` - Controls which format this converter will serialize decimals in. This value is case insensitive and can be either `BASE64` (default) or `NUMERIC`. This should be set to `BASE64`. For more details on Decimal handling see [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-decimal-types).

The following key configuration properties are required for the Debezium connector to work with ClickHouse. **Important:** We configure the connector to track changes at a per table level:

- [`name`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-name) - Unique name for the connector. Attempting to register again with the same name will fail. This property is required by all Kafka Connect connectors.
- [`connector.class`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-connector-class) - Always set to value `io.debezium.connector.postgresql.PostgresConnector` (self-managed only)
- [`database.hostname`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-hostname) - Hostname not including port.
- [`database.port`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-port)
- [`database.user`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-user)
- [`database.password`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-password)
- [`database.dbname`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-dbname)
- [`database.sslmode`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-database-sslmode) - `require` for Cloud databases.
`publication.autocreate.mode`
- [`database.server.name`](https://docs.confluent.io/kafka-connectors/debezium-postgres-source/current/postgres_source_connector_config.html#auto-topic-creation) - Logical name that identifies and provides a namespace for the particular PostgreSQL database server/cluster being monitored. The logical name should be unique across all other connectors, since it is used as a prefix for all Kafka topic names coming from this connector. For our example, we use the value `postgres`.
- [`tasks.max`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-tasks-max) - Always 1
- [`plugin.name`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-plugin-name) - The name of the PostgreSQL logical decoding plug-in installed on the PostgreSQL server. We recommend `pgoutput`.
- [`slot.name`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-slot-name) - Logical decoding slot name. Must be unique to a Database+schema. If replicating only one, use `debezium`.
- [`slot.drop.on.stop`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-slot-drop-on-stop) - Set to `false` in production. `true` can be useful during testing - see docs.
- [`publication.name`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-publication-name) - The name of the PostgreSQL publication created for streaming changes when using pgoutput. This will be created on startup if you have configurd the Postgres user to have [sufficient permissions](#configure-postgres). Alternatively, it can be pre-created. `dbz_publication` default can be used.
- [`table.include.list`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-table-include-list) - An optional, comma-separated list of regular expressions that match fully-qualified table identifiers for tables whose changes you want to capture. Ensure format is `<schema_name>.<table_name>`. For our example we use `public.uk_price_paid`. **IMPORTANT: We assume table level replication. Only one table can be specified in this parameter.**
- [`tombstones.on.delete`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-tombstones-on-delete) - Controls whether a delete event is followed by a tombstone event. Set to `false`. Can be set to `true` if you are interested in using [log compaction](https://kafka.apache.org/documentation/#compaction) - this requires you to drop these tombstones in the ClickHouse Sink.
- [`publication.autocreate.mode`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-publication-autocreate-mode) - Set to `filtered`. This causes a publication to be created for only the table in the property `table.include.list` to be created. Further details [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-publication-autocreate-mode).
- [`snapshot.mode`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-snapshot-mode) We utilise `never` for the snapshot mode - since we loaded the initial data using the `postgres` function. This is typically significantly faster. This does, however, require no changes to be made to our Postgres data whilst copying the rows to ClickHouse. Users can utilize the `initial` mode if they are unable to pause changes to their Postgres instance. This will ensure the full state of the data is replayed before changes are sent - these rows will be sent as `op=r` and appear identical to create operatons.
- [`decimal.handling.mode`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-decimal-types). Specifies how the connector should handle values for DECIMAL and NUMERIC columns. The default value of `precise` will encode these in their binary form i.e. java.math.BigDecimal. Combined with the `decimal.format` setting above this will cause these to be output in the JSON as numeric. Users may wish to adjust depending on the precision required.
- [topic.prefix](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-topic-prefix) - Topic prefix that provides a namespace for the particular PostgreSQL database server or cluster in which Debezium is capturing changes. The prefix should be unique across all other connectors, since it is used as a topic name prefix for all Kafka topics that receive records from this connector. This should not be changed once set. We do not set in our example and leave empty.

The following settings will impact the delay between changes in Postgres and their arrival time in ClickHouse. Consider these in the context of required SLAs and efficient batching to ClickHouse - see [Other Considerations](#other-considerations).

- [max.batch.size](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-max-batch-size) - maximum size of each batch of events.
- [max.queue.size](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-max-queue-size) - queue size before sending events to Kafka. Allows backpressure. Should be greater than batch size.
- [poll.interval.ms](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-max-queue-size) - Positive integer value that specifies the number of milliseconds the connector should wait for new change events to appear before it starts processing a batch of events. Defaults to 500 milliseconds.

A full list of configuration parameters can be found [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-connector-properties). Confluent provides [additional documentation](https://docs.confluent.io/kafka-connectors/debezium-postgres-source/current/postgres_source_connector_config.html#auto-topic-creation) for those deploying using the Confluent Kafka or Cloud.

A Debezium connector can be configured in Confluent Cloud as shown below. This connector will automatically create a Kafka topic when messages are received. 

![Configure Debezium](https://github.com/ClickHouse/examples/blob/main/cdc/postgresql/debezium_configuration.gif?raw=true)

The associated JSON configuration is shown below and can be used with the steps documented [here](https://docs.confluent.io/cloud/current/connectors/cc-postgresql-cdc-source-debezium.html):

```json
{
  "connector.class": "PostgresCdcSource",
  "name": "uk_price_paid_changes",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "WI6TG2IRAPVU5N4W",
  "kafka.api.secret": "****************************************************************",
  "database.hostname": "debezium.cviz0mg5aual.us-east-2.rds.amazonaws.com",
  "database.port": "5432",
  "database.user": "postgres",
  "database.password": "********************************",
  "database.dbname": "postgres",
  "database.server.name": "postgres",
  "database.sslmode": "require",
  "publication.name": "dbz_publication",
  "publication.autocreate.mode": "filtered",
  "table.include.list": "public.uk_price_paid",
  "snapshot.mode": "never",
  "tombstones.on.delete": "false",
  "plugin.name": "pgoutput",
  "slot.name": "debezium",
  "poll.interval.ms": "1000",
  "max.batch.size": "1000",
  "event.processing.failure.handling.mode": "fail",
  "heartbeat.interval.ms": "0",
  "provide.transaction.metadata": "false",
  "decimal.handling.mode": "precise",
  "binary.handling.mode": "bytes",
  "time.precision.mode": "adaptive",
  "cleanup.policy": "delete",
  "hstore.handling.mode": "json",
  "interval.handling.mode": "numeric",
  "schema.refresh.mode": "columns_diff",
  "output.data.format": "JSON",
  "after.state.only": "false",
  "output.key.format": "STRING",
  "json.output.decimal.format": "BASE64",
  "tasks.max": "1",
  "transforms": "flatten,set_topic",
  "transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten$Value",
  "transforms.flatten.delimiter": ".",
  "transforms.set_topic.type": "io.confluent.connect.cloud.transforms.TopicRegexRouter",
  "transforms.set_topic.regex": ".*",
  "transforms.set_topic.replacement": "uk_price_paid_changes"
}
```

**Important: Note the important settings above**:

- We set the `after.state.only` property to `false`. This settings appears specific to Confluent Cloud and must be set as `false` to ensure the previous values of rows are provided as well as the LSN number.

- We also utilize the SMT capabilities of Kafka connect to [flatten](https://kafka.apache.org/documentation/#org.apache.kafka.connect.transforms.Flatten) the messages and set the Kafka topic. This can be achieved in self-manage through configuration. Further details [here](https://debezium.io/documentation/reference/stable/transformations/topic-routing.html#_example) and [here](https://kafka.apache.org/documentation/#connect_transforms).

Self-managed installation instructions can be found [here](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-deployment).

## Configure Kafka Sink

Use either of the following approaches for sending data to ClickHouse. Importantly, messages should be sent to the `uk_price_paid_changes` table and **NOT** the `uk_price_paid` table. This ensures our materialized view is triggered and the messages transformed.

The principle advantage of the ClickHouse Kafka Connect Sink is its exactly-once semantics. To deploy in Confluent Cloud, however, it requires users to upload the package and use Confluent's "Bring your own connector" offering. The HTTP Sink, conversely can be simpler to operate and is natively supported in Confluent Cloud.

Both examples below assume the user has configured the Debezium connector to send data to the topic `uk_price_paid_changes`.

### ClickHouse Kafka Connect Sink

We show configuring the ClickHouse Kafka Connect Sink in Confluent Cloud below. Note the connector package can be downloaded from [here](https://github.com/ClickHouse/clickhouse-kafka-connect/releases).

![ClickHouse Sink Configuration](https://github.com/ClickHouse/examples/blob/main/cdc/postgresql/clickhouse_sink_configuration.gif?raw=true)

The JSON configuration is shown below:

```json
{
  "database": "default",
  "exactlyOnce": "false",
  "hostname": "cbupclfpbv.us-east-2.aws.clickhouse-staging.com",
  "password": "****************",
  "port": "8443",
  "schemas.enable": "false",
  "security.protocol": "SSL",
  "ssl": "true",
  "topics": "uk_price_paid_changes",
  "username": "default",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

Details on deploying this connector in self-managed environments can be found [here](https://clickhouse.com/docs/en/integrations/kafka#clickhouse-kafka-connect-sink).


### HTTP Sink (Confluent Cloud only)

The HTTP Sink is a native connector to Confluent Cloud. We show configuring this connector below but also suggest users read [the supporting documentation]() for configuring this sink with ClickHouse.

![HTTP Sink Configuration](https://github.com/ClickHouse/examples/blob/main/cdc/postgresql/http_connector_configuration.gif?raw=true)

The JSON configuration is shown below:

```json
{
  "topics": "uk_price_paid_changes",
  "input.data.format": "JSON",
  "connector.class": "HttpSink",
  "name": "ClickHouse HTTP Sink",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "5RRHQMJGUZF4ZNSJ",
  "kafka.api.secret": "****************************************************************",
  "http.api.url": "https://cbupclfpbv.us-east-2.aws.clickhouse-staging.com:8443?query=INSERT%20INTO%20default.uk_price_paid_changes%20FORMAT%20JSONEachRow",
  "request.method": "POST",
  "behavior.on.null.values": "ignore",
  "behavior.on.error": "ignore",
  "report.errors.as": "error_string",
  "request.body.format": "json",
  "batch.max.size": "1000",
  "batch.json.as.array": "true",
  "auth.type": "BASIC",
  "connection.user": "default",
  "connection.password": "*************",
  "oauth2.token.property": "access_token",
  "oauth2.client.auth.mode": "header",
  "oauth2.client.scope": "any",
  "oauth2.jwt.enabled": "false",
  "oauth2.jwt.keystore.type": "JKS",
  "retry.on.status.codes": "400-",
  "max.retries": "3",
  "retry.backoff.ms": "3000",
  "http.connect.timeout.ms": "30000",
  "http.request.timeout.ms": "30000",
  "https.ssl.protocol": "TLSv1.3",
  "https.host.verifier.enabled": "true",
  "tasks.max": "1"
}
```

Attention is drawn to the settings `http.api.url`, `request.body.format` and `batch.json.as.array`. The former of these requires the a URL encoded ClickHouse URL containing the database name and `FORMAT` as `JSONEachRow`. Further details [here](https://clickhouse.com/docs/en/integrations/kafka#confluent-http-sink-connector). The latter 2 settings ensure the rows are sent as JSON. The setting `batch.max.size` can be used to tune the batch size.


## Querying in ClickHouse

At [merge time](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree) the ReplacingMergeTree removes rows, retaining the highest version, with the same `ORDER BY` values. Deleted rows should also be removed (see [below](#important-note-regards-deletes)). This, however, offers eventual correctness only - it doesnot guarantee rows will be deduplicated and you should not rely on it.

To obtain correct answers, users will need to complement background merges with query time deduplication. This can be achieved using one of two methods:

1. Modify queries to utilize only the latest version of each row and filter deletes. For example, consider the queries below. The former utilizes all rows and returns (potentially) the wrong answer. The latter uses only the latest version of each row.

```sql
SELECT avg(price)
FROM uk_price_paid

┌─────────avg(price)─┐
│ 214352.47087590597 │
└────────────────────┘

1 row in set. Elapsed: 0.045 sec. Processed 27.74 million rows, 110.94 MB (615.08 million rows/s., 2.46 GB/s.)

SELECT avg(price)
FROM
(
    SELECT argMax(price, version) AS price
    FROM uk_price_paid
    GROUP BY id
)
┌─────────avg(price)─┐
│ 214352.57845933954 │
└────────────────────┘

1 row in set. Elapsed: 0.426 sec. Processed 27.74 million rows, 554.70 MB (65.11 million rows/s., 1.30 GB/s.)

```

2. Utilize the `FINAL` modifier after the table name. This will perform query time de-duplication. Provided the query filters rows effectively, avoiding full table scans, this can be performant. Full table scans, however, maybe appreciably impacted. Note how the below query is slower than the adapted query above.

```sql
SELECT avg(price)
FROM uk_price_paid
FINAL

┌─────────avg(price)─┐
│ 214352.57845933954 │
└────────────────────┘

1 row in set. Elapsed: 0.671 sec. Processed 29.65 million rows, 1.35 GB (44.20 million rows/s., 2.01 GB/s.)
```

## Testing

To test we utilize a custom Python script which makes random changes to the Postgres rows - adding, updating and deleting rows. Specifically, regards updates, this script changes the `type`, `price` and `is_new` column for random rows. The full code and dependencies can found [here](https://github.com/ClickHouse/examples/blob/main/cdc/postgresql/randomize.py).

```bash
export PGDATABASE=<database>
export PGUSER=postgres
export PGPASSWORD=<password>
export PGHOST=<host>
export PGPORT=5432
pip3 install -r requirements.txt
python randomize.py --iterations 1 --weights "0.4,0.4,0.2" --delay 0.5
```

Note the `weights` parameter and value `0.4,0.4,0.2` denotes the rato of creates, updates and deletes. The `delay` parameter sets the time delay between each operation (default 0.5 secs). `iterations` sets the total number of changes to make to the table. In the example above, we modify 1000 rows.

Once the script has complete we can run the following queries against Postgres and ClickHouse to confirm consistency. The responses shown may differ from your values, as changes are random. The values from both databases should, however, be identical. We utilize `FINAL` for simplicity.

#### Identical row count

```sql
-- Postgres
postgres=> SELECT count(*) FROM uk_price_paid;
  count
----------
 27735027
(1 row)


-- ClickHouse
SELECT count()
FROM uk_price_paid
FINAL

┌──count()─┐
│ 27735027 │
└──────────┘
```

#### Same price statistics

```sql
-- Postgres
postgres=> SELECT sum(price) FROM uk_price_paid;
      sum
---------------
 5945061701495
(1 row)

-- ClickHouse
SELECT sum(price)
FROM uk_price_paid
FINAL

┌────sum(price)─┐
│ 5945061701495 │
└───────────────┘
```

#### Same number of new properties

```sql
-- Postgres
postgres=> SELECT sum(is_new) FROM uk_price_paid;
   sum
---------
 2845557
(1 row)


-- ClickHouse
SELECT sum(is_new)
FROM uk_price_paid
FINAL

┌─sum(is_new)─┐
│     2845557 │
└─────────────┘
```

### Same house price distribution 

```sql
-- Postgres
postgres=> SELECT type, count(*) c FROM uk_price_paid GROUP BY type;
     type      |    c
---------------+---------
 detached      | 6399743
 flat          | 4981171
 other         |  419212
 semi-detached | 7597039
 terraced      | 8337862
(5 rows)


-- ClickHouse
SELECT
    type,
    count() AS c
FROM uk_price_paid
FINAL
GROUP BY type

┌─type──────────┬───────c─┐
│ other         │  419212 │
│ terraced      │ 8337862 │
│ semi-detached │ 7597039 │
│ detached      │ 6399743 │
│ flat          │ 4981171 │
└───────────────┴─────────┘
```


## Other Considerations

- The Debezium connector will batch row changes where possible, upto a max size of the `max.batch.size`. These batches are formed every poll interval `poll.interval.ms` (500ms default). Users can increase these values for larger and more efficient batches at the expense of higher end-to-end latency. Remember that ClickHouse [prefers batches of atleast 1000](https://clickhouse.com/docs/en/cloud/bestpractices/bulk-inserts) to avoid common issues such as [too many parts](https://clickhouse.com/docs/knowledgebase/exception-too-many-parts). For low throughput environments (<100 rows per second) this batching is not as critical as ClickHouse will likely keep up with merges. However, users should avoid small batches at a high rate of insert. 

Batching can also be configured on the Sink side for the HTTP connector. This is currently not supported explictly in the ClickHouse Sink, but can be configured through the Kafka connect framework - see the setting [`consumer.override.max.poll.records`](https://docs.confluent.io/platform/current/installation/configuration/consumer-configs.html#max-poll-records). Alternatively, users can configure [ClickHouse Async inserts](https://clickhouse.com/docs/en/optimize/asynchronous-inserts#enabling-asynchronous-inserts) and allow ClickHouse to batch. In this mode, inserts can be sent as small batches to ClickHouse which will batch rows before flushing. Note that while flushing, rows will not be searchable. This approach therefore does **not** help with end-to-end latency.
- Users should be cognizant of [WAL disk usage](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-wal-disk-space) and the importance of [`heartbeat.interval.ms`](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-heartbeat-interval-ms) in cases where tables with few changes are being monitored in databases with many updates. 
- Normally the primary key in a ClickHouse table is denoted by the `ORDER BY` clause. For performance, this is held in memory. The use of the `ORDER BY` key for deduplication in the ReplacingMergeTree can cause this to become long, increasing memory usage. If this becomes a concern, users can utilize the `PRIMARY KEY` clause. This should be prefix of the `ORDER BY` clause. While the data will be sorted on disk, according to the `ORDER BY` (maximizing compression and ensuring uniqueness), only the columns in the `PRIMARY KEY` will be held in memory. Using this approach, the Postgres primary key columns can be omitted from the `PRIMARY KEY` - saving memory without impacting query performance.
- We recommened users partition their table according to [best practices](https://clickhouse.com/docs/en/optimize/partitioning-key). If users can ensure this partitioning key does not change, updates pertaining to the same row will be sent to the same ClickHouse partition. Assuming this is the case, users can use the parameter `do_not_merge_across_partitions_select_final` at query time to improve performance.

## Limitations 

- The above approach does not currently support **Postgres primary key changes**. To implement this, users will need to detect `op=delete` messages from Debezium which have no `before` or `after` fields. The `id` should then be used to delete these rows in ClickHouse - preferably using [Lightweight deletes](https://clickhouse.com/docs/en/guides/developer/lightweght-delete). This requires custom code instead of using the Kafka sink/HTTP sink for sending data to ClickHouse.
- The columns used in the `ORDER BY` clause of the ClickHouse table cannot change in origin Postgres table. These are used by the `ReplacingMergeTree` to identify duplicate rows. Choose these columns carefully and ensure - optimize them for ClickHouse access patterns and search performance, while making sure they are immutable in Postgres.
- If the Primary key of a table changes, users will likely need to create a new ClickHouse table with the new column as part of the `ORDER BY` clause. Note this also requires a [process to be performed for the Debezium connector](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-streaming-changes). 
- The logical decoding, on which the Debezium connector depends, does not support DDL changes. This means that the connector is unable to report DDL change events back to consumers.
- Logical decoding replication slots are supported on only primary servers. When there is a cluster of PostgreSQL servers, the connector can run on only the active primary server. It cannot run on hot or warm standby replicas. If the primary server fails or is demoted, the connector stops. After the primary server has recovered, you can restart the connector. If a different PostgreSQL server has been promoted to primary, adjust the connector configuration before restarting the connector.
- While Kafka Sinks can be safely scaled to use more workers, the Debezium connector allows only a [single task](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-tasks-max). The solution proposed above uses a connector per table, allowing the solution to be scaled at a table level.
- The documented approach assumes a connector instance per table. We currently donot support a connector monitoring several tables - although this maybe achievable with topic routing i.e. messages are routed to a table specific topic. This configuration has not yet been tested.

### Important note regards deletes

Our previous example used the default value of `Never` for the setting `clean_deleted_rows`, when creating the `uk_price_paid` table in ClickHouse. This means deleted rows will never be deleted. The setting `clean_deleted_rows` with value `Always` is required for the `ReplacingMergeTree` to delete rows on merges. As of `22.4` this feature has a bug where the wrong rows can be removed. We therefore recommend using the value `Never` as shown - this will cause delete rows to accumulate but may be acceptable if low volumes. To forcibly remove deleted rows, users can periodically scheduled an `OPTIMIZE FINAL CLEANUP` operation on the table i.e.

This should be done with caution (ideally during idle periods), since it can cause significant IO on large tables.

**We are actively addressing [this issue](https://github.com/ClickHouse/ClickHouse/issues/50346).**

