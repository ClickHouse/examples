# Null Table Engine

Video: https://www.youtube.com/watch?v=vaY5LQ7a_Dk

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Generate data:

```bash
pip install faker jsonlines
```

```bash
python datagen.py > logs.json
```

Describe logs file:

```sql
DESCRIBE 'logs.json'
SETTINGS describe_compact_output=1,
         schema_inference_make_columns_nullable=0;
```


Create `logs` table:

```sql
CREATE TABLE logs (
  timestamp DateTime64(3),
  service String,
  logLevel String,
  `X-Correlation-ID` String,
  message String
)
ENGINE=Null;
```

Create `searches` table:

```sql
CREATE TABLE searches (
    timestamp DateTime(3),
    userId String,
    location String,
    checkin Date,
    checkout Date,
    guests Int
)
ORDER BY timestamp;
```

Create `bookings` table:

```sql
CREATE TABLE bookings (
    timestamp DateTime(3),
    userId String,
    roomType LowCardinality(String),
    price UInt16,
    checkin Date,
    checkout Date
)
ORDER BY timestamp;
```

Materialized views:

```sql
CREATE MATERIALIZED VIEW searches_mv TO searches AS
WITH searchLogs AS (
  FROM logs
  SELECT timestamp, extractAllGroups(
    assumeNotNull(message),
    'User (.*) searching available hotels with criteria: (.*)\.'
    )[1] AS groups,
    groups[1] AS userId,
    JSONExtract(groups[2], 'Map(String, Variant(String, Int))') as search
  WHERE service = 'Search'
)
FROM searchLogs
SELECT timestamp,
       userId,
       search['location'] AS location,
       search['checkin'] AS checkin,
       search['checkout'] AS checkout,
       search['guests'] AS guests;
```

```sql
CREATE MATERIALIZED VIEW bookings_mv TO bookings AS
WITH bookingLogs AS (
  FROM logs
  SELECT timestamp, extractAllGroups(
    assumeNotNull(message),
    'User (.*) selected a hotel room with details: (.*)\.'
    )[1] AS groups,
    groups[1] AS userId,
    JSONExtract(groups[2], 'Map(String, Variant(String, Int))') as booking
  WHERE service = 'Booking'
)
FROM bookingLogs
SELECT timestamp,
       userId,
       booking['roomType'] AS roomType,
       booking['price'] AS price,
       booking['checkin'] AS checkin,
       booking['checkout'] AS checkout;
```

Insert data into the `logs` table:

```sql
INSERT INTO logs
SELECT * FROM 'logs.json'
```

Queries:

```sql
WITH userCount AS (
  SELECT userId, count(*) AS numberOfSearches
  FROM searches
  GROUP BY userId
)
SELECT numberOfSearches, count() AS count
FROM userCount
GROUP BY numberOfSearches
ORDER BY count DESC
LIMIT 10;
```

```sql
SELECT roomType, count(), avg(price)
FROM bookings 
GROUP BY ALL;
```