# Ingesting data with the Golang driver

In this recipe, we're going to learn how to ingest data into ClickHouse using the Golang driver.

## Download Clickhouse

```bash
curl https://clickhouse.com/ | sh
```

## Setup ClickHouse

Launch ClickHouse Server

```bash
./clickhouse server
```

## Create table

Connect to the ClickHouse Server

```bash
./clickhouse client -m
```

Create table

```sql
CREATE TABLE IF NOT EXISTS performance
(
    `quadKey` String,
    `tileWKT` String EPHEMERAL,
    `tile` Ring DEFAULT readWKTPolygon(if(tileWKT = '', 'POLYGON()', tileWKT))[1],
    `tileX` Float,
    `tileY` Float,
    `downloadSpeedKbps` UInt32,
    `uploadSpeedKbps` UInt32,
    `latencyMs` UInt32,
    `downloadLatencyMs` UInt32,
    `uploadLatencyMs` UInt32,
    `tests` UInt32,
    `devices` UInt16
)
ENGINE = MergeTree
ORDER BY tileX;
```

## Download CSV file

Download `performance.csv.gz`

```bash
wget https://datasets-documentation.s3.eu-west-3.amazonaws.com/ookla/performance.csv.gz
gunzip performance.csv.gz
```

## Install driver

The driver dependency is defined in [go.mod](go.mod). 
You can install it by running the following:

```bash
go mod tidy
```

## Ingest data

[main.go](main.go) contains code that iterates over the CSV file and ingests into ClickHouse in batches of 1,000 records.

```bash
    time go run ingest.go csvreader.go
```

You should see output similar to this:

```text
go run main.go  8.68s user 2.79s system 75% cpu 15.294 total
```
