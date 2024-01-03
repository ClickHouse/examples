# ClickHouse and MSSQL

1 single ClickHouse Instance configured with 1 MSSQL instance with a sample table named Customer.

This uses ODBC connection setup in ClickHouse container via FreeTDS driver.

Once launch completes, you can connect to clickhouse:

```
clickhouse client
ClickHouse client version 23.2.1.993 (official build).
Connecting to localhost:9000 as user default.
Connected to ClickHouse server version 23.10.5 revision 54466.

ClickHouse client version is older than ClickHouse server. It may lack support for new features.
```

and issue SQL statements against `default.odbc_customer` table:

```sql
ch_mssql :) SHOW CREATE TABLE odbc_customer;

SHOW CREATE TABLE odbc_customer

Query id: 2bcd328b-3599-45e2-ab2e-35d2da8b67b8

┌─statement──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ CREATE TABLE default.odbc_customer
(
    `customer_id` UInt64,
    `firstname` String,
    `lastname` String,
    `email` String,
    `created_date` DateTime
)
ENGINE = ODBC('DSN=ch_mssql;port=1433;Uid=sa;Pwd=Mssql_Password123;Database=master', 'dbo', 'Customer') │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

1 row in set. Elapsed: 0.003 sec.

ch_mssql :) SELECT * FROM odbc_customer;

SELECT *
FROM odbc_customer

Query id: 33615ba0-1a0a-4d93-ba5b-d3d126fd45f5

┌─customer_id─┬─firstname─┬─lastname─┬─email────────────────┬────────created_date─┐
│           1 │ Jonah     │ Hook     │ jonah@clickhouse.db  │ 2021-09-01 00:00:00 │
│           2 │ Mary      │ Brown    │ mary@clickhouse.db   │ 2012-12-01 00:00:00 │
│           3 │ Russell   │ White    │ rwhite@clickhouse.db │ 2018-07-01 00:00:00 │
│           4 │ Dan       │ Red      │ dan@clickhouse.db    │ 2011-09-01 00:00:00 │
│           5 │ Alice     │ Black    │ alice@clickhouse.db  │ 2011-09-01 00:00:00 │
└─────────────┴───────────┴──────────┴──────────────────────┴─────────────────────┘

5 rows in set. Elapsed: 0.006 sec.

ch_mssql :) SELECT * FROM odbc('DSN=ch_mssql;port=1433;Uid=sa;Pwd=Mssql_Password123;Database=master','Customer');

SELECT *
FROM odbc('DSN=ch_mssql;port=1433;Uid=sa;Pwd=Mssql_Password123;Database=master', 'Customer')

Query id: 47049a0f-b898-44a1-aa58-32fa78d3fdb0

┌─customer_id─┬─firstname─┬─lastname─┬─email────────────────┬────────created_date─┐
│           1 │ Jonah     │ Hook     │ jonah@clickhouse.db  │ 2021-09-01 00:00:00 │
│           2 │ Mary      │ Brown    │ mary@clickhouse.db   │ 2012-12-01 00:00:00 │
│           3 │ Russell   │ White    │ rwhite@clickhouse.db │ 2018-07-01 00:00:00 │
│           4 │ Dan       │ Red      │ dan@clickhouse.db    │ 2011-09-01 00:00:00 │
│           5 │ Alice     │ Black    │ alice@clickhouse.db  │ 2011-09-01 00:00:00 │
└─────────────┴───────────┴──────────┴──────────────────────┴─────────────────────┘

5 rows in set. Elapsed: 0.026 sec.
```
