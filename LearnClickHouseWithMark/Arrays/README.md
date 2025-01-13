# Having fun with arrays

Video: https://youtu.be/7jaw3J6U_h8

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse Local

```bash
./clickhouse -m
```

```
SET output_format_pretty_row_numbers=0;
```

```sql
SELECT *
FROM file('strava_Splits.csv')
LIMIT 3;
```

```sql
WITH groupArray(timePerMile) AS pace_array
SELECT id, pace_array
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arrayDifference(pace_array) AS pace_diff
SELECT id, pace_array, pace_diff
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arraySlice(arrayDifference(pace_array), 2) AS pace_diff
SELECT id, pace_array, pace_diff
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arraySlice(arrayDifference(pace_array), 2) AS pace_diff,
     arrayMax(pace_diff) AS biggestIncrease,
     arrayMin(pace_diff) AS biggestDecrease
SELECT id, pace_array, pace_diff, biggestIncrease, biggestDecrease
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
SELECT name, create_query
FROM system.functions
WHERE origin = 'SQLUserDefined'
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arraySlice(arrayDifference(pace_array), 2) AS pace_diff,
     arrayMax(pace_diff) AS biggestIncrease,
     arrayMin(pace_diff) AS biggestDecrease
SELECT id, pace_array, pace_diff, biggestIncrease, biggestDecrease
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arraySlice(arrayDifference(pace_array), 2) AS pace_diff,
     arrayMax(pace_diff) AS biggestIncrease,
     arrayMin(pace_diff) AS biggestDecrease,
     arrayMap(x -> (
         drawBlock(getRGB(x, biggestIncrease, biggestDecrease, 0.8))
     ), pace_diff) AS rgb
SELECT id, rgb
FROM file('strava_Splits.csv')
GROUP BY ALL
LIMIT 3
FORMAT Vertical;
```

```sql
WITH groupArray(timePerMile) AS pace_array,
     arraySlice(arrayDifference(pace_array), 2) AS pace_diff,
     arrayMax(pace_diff) AS biggestIncrease,
     arrayMin(pace_diff) AS biggestDecrease,
     arrayMap(x -> (
         drawBlock(getRGB(x, biggestIncrease, biggestDecrease, 0.8))
     ), pace_diff) AS rgb
SELECT id, startDate, arrayStringConcat(rgb) AS paceViz
FROM file('strava_Splits.csv')
GROUP BY ALL
ORDER BY startDate DESC
LIMIT 10;
```

```sql

```