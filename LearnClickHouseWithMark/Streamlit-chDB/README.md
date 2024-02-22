# Interactive Streamlit app with chdb

In this recipe, we'll learn how to create an interactive Streamlit app to analyse energy usage with chdb.

## Generate data

Generate usage data

```bash
poetry run python datagen.py
```

This writes data into `data.csv`

## Download Clickhouse

```bash
curl https://clickhouse.com/ | sh
```

## Setup ClickHouse

Launch ClickHouse Local

```bash
./clickhouse local -m --path energy.chdb
```


## Ingest data

```sql
CREATE DATABASE energy;
```

```sql
CREATE TABLE IF NOT EXISTS energy.tariffs 
ENGINE = MergeTree
ORDER BY day 
AS
SELECT arrayJoin(arrayMap(
    x -> addDays(startDate, x),
    range(dateDiff('days', startDate, endDate) + 1)
)) AS day, *
FROM file(`data/tariffs.csv`)
SETTINGS schema_inference_make_columns_nullable=0;
```

```sql
CREATE TABLE energy.usage
ENGINE = MergeTree
ORDER BY epochTimestamp AS
SELECT *
FROM `data/data.csv`
SETTINGS schema_inference_make_columns_nullable=0;
```

## Launch Streamlit app

Make sure you exit ClickHouse Local first (type `exit;`)

```bash
poetry run streamlit run app.py --server.headless true
```

Open http://localhost:8501