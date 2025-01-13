# PIVOT

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse Local

```bash
./clickhouse -m
```

```sql
SELECT sumMap(map('ClickHouse', 1, 'ClickBench', 2));
```


```sql
WITH values AS (
  SELECT map('ClickHouse', 3) AS value
  UNION ALL
  SELECT map('ClickBench', 2, 'ClickHouse', 4) AS value
)
SELECT sumMap(value)
FROM values;
```

```sql
WITH values AS (
  SELECT map('ClickHouse', 3) AS value
  UNION ALL
  SELECT map('ClickBench', 2, 'ClickHouse', 4) AS value
)
SELECT maxMap(value)
FROM values;
```

```sql
WITH values AS (
  SELECT map('ClickHouse', 3) AS value
  UNION ALL
  SELECT map('ClickBench', 2, 'ClickHouse', 4) AS value
)
SELECT avgMap(value)
FROM values;
```

Connect ClickHouse Client to the SQL playground

```bash
./clickhouse client -m \
  -h sql-clickhouse.clickhouse.com \
  -u demo \
  --secure \
  -- --output_format_pretty_row_numbers=0
```

```sql sleepBefore=1.0
SELECT * 
FROM uk.uk_price_paid 
LIMIT 1 
FORMAT Vertical;
```

Median:

```sql
WITH pricesByDecade AS (
  SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
  FROM uk.uk_price_paid
)
SELECT
    county,
    medianMap(map(year, price)) AS medianPrices
FROM pricesByDecade
GROUP BY ALL
ORDER BY max(price) DESC
LIMIT 10;
```

Filter to years greater than or equal to 2010

```sql
WITH pricesByDecade AS (
  SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
  FROM uk.uk_price_paid
)
SELECT
    county,
    medianMap(map(year, price)) AS medianPrices
FROM pricesByDecade
WHERE year >= 2010
GROUP BY ALL
ORDER BY max(price) DESC
LIMIT 10;
```

Median and max:

```sql
WITH pricesByDecade AS (
  SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
  FROM uk.uk_price_paid
)
SELECT
    county,
    medianMap(map(year, price)) AS medianPrices,
    maxMap(map(year, price)) AS maxPrices
FROM pricesByDecade
WHERE year >= 2010
GROUP BY ALL
ORDER BY max(price) DESC
LIMIT 10;
```

Median and average:

```sql
WITH pricesByDecade AS (
  SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
  FROM uk.uk_price_paid
)
SELECT
    county,
    medianMap(map(year, price)) AS medianPrices,
    mapApply((k, v) -> (k, floor(v)), avgMap(map(year, price))) AS avgPrices
FROM pricesByDecade
WHERE year >= 2010
GROUP BY ALL
ORDER BY max(price) DESC
LIMIT 10;
```

Group by country/district:

```sql
WITH pricesByDecade AS (
    SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
    FROM uk.uk_price_paid
)
SELECT
    county, district,
    medianMap(map(year, price)) AS medianPrices
FROM pricesByDecade
WHERE year >= 2010
GROUP BY ALL
ORDER BY median(price) DESC
LIMIT 10
```

NP1 postcode:

```sql
WITH pricesByDecade AS (
    SELECT year(toStartOfInterval(date, toIntervalYear(10))) AS year, *
    FROM uk.uk_price_paid
)
SELECT
    year,
    medianMap(map(postcode1 || ' ' || postcode2, price)) AS medianPrices
FROM pricesByDecade
WHERE postcode1 LIKE 'NP1'
GROUP BY ALL
ORDER BY year
```