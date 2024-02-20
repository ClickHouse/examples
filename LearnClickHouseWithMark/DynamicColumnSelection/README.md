# Dynamic Column Selection

Video: https://www.youtube.com/watch?v=moabRqqHNo4

Download Yellow Taxi Trip Records from https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Create a database and ingest data

```sql
CREATE DATABASE Taxis;
```

```sql
CREATE TABLE Taxis.trips 
ENGINE MergeTree 
ORDER BY (tpep_pickup_datetime) AS 
from file('yellow tripdata Jan 2023.parquet', Parquet)
select *
SETTINGS schema_inference_make_columns_nullable = 0;
```

Get all the amount columns

```sql
FROM trips 
SELECT COLUMNS('.*_amount')
LIMIT 10;
```

amount/fee/tax

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
LIMIT 10;
```

Max of all the amount columns

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
  APPLY(max);
```

Average of all the amount columns

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
  APPLY(avg);
```

Rounding (chaining functions)

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
  APPLY(avg)
  APPLY(round)
FORMAT Vertical;
```

Rounding to 2 dp (lambda)

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
  APPLY(avg)
  APPLY(col -> round(col, 2))
FORMAT Vertical;
```

Replace a field value

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax')
  REPLACE(total_amount*2 AS total_amount) 
  APPLY(avg)
  APPLY(col -> round(col, 2))
FORMAT Vertical;
```

Exclude a field

```sql
FROM trips 
SELECT 
  COLUMNS('.*_amount|fee|tax') EXCEPT(tolls_amount)
  REPLACE(total_amount*2 AS total_amount) 
  APPLY(avg)
  APPLY(col -> round(col, 2))
FORMAT Vertical;
```