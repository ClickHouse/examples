# Querying data in archive files

Video: https://www.youtube.com/watch?v=CiKfRMAhs3M

Download dataset from https://www.kaggle.com/datasets/jacksoncrow/stock-market-dataset

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Find file names

```sql
FROM file('data/Stock Market Dataset.zip :: **', One)
SELECT _file
LIMIT 5;
```

Get the list of top-level files and directories

```sql
WITH files AS (
    FROM file('data/Stock Market Dataset.zip :: **', One)
    SELECT _file, splitByChar('/', _file) AS parts
)
FROM files
SELECT if(length(parts) == 1,
        parts[1],
        arrayStringConcat(arraySlice(parts, 1, -1), '/')
    ) AS fileOrDir,
    count()
GROUP BY ALL;
```

Create symbols table

```sql
CREATE TABLE symbols 
Engine=MergeTree
ORDER BY Symbol AS 
FROM file('data/Stock Market Dataset.zip :: symbols_valid_meta.csv', CSVWithNames)
SELECT * 
SETTINGS schema_inference_make_columns_nullable=0;
```

Create prices table

```sql
CREATE TABLE prices 
Engine=MergeTree
ORDER BY (symbol, Date) AS
FROM file('data/Stock Market Dataset.zip :: {etfs,stocks}/*', CSVWithNames)
SELECT extractAllGroups(_file,'.*\/(.*)\.csv')[1][1] AS symbol, 
       * REPLACE (toInt64(Volume) as Volume)
SETTINGS schema_inference_make_columns_nullable=0, input_format_try_infer_integers=0;
```

Trading volume from January 2020 to March 2020

```sql
FROM prices
JOIN symbols on symbols.Symbol = prices.symbol
SELECT toStartOfMonth(Date) AS month,
       ETF,
       sum(Volume) AS totalVolume,
       formatReadableQuantity(totalVolume) AS readableVolume
WHERE month IN ('2020-01-01', '2020-02-01', '2020-03-01')
GROUP BY ALL
ORDER BY month, ETF DESC;
```