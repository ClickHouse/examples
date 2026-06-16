# Query a Parquet file from the command line

Runnable companion to **[How to query a Parquet file from the command line](https://clickhouse.com/resources/engineering/how-to-query-parquet-file)**.

Read and aggregate a `.parquet` file with `clickhouse local` — no server, no schema, no import.

## Run it

```bash
./generate.sh   # builds data/data.parquet, data/data.zstd.parquet, data/events_large.parquet (~1 GB)
./run.sh        # view / describe / filter+aggregate / read compressed / perf
```

`generate.sh` builds the sample data with `clickhouse local` itself (nothing large is committed).
`run.sh` contains the exact commands from the article. `expected_output.txt` is what you should see.

## The one-liner

```bash
clickhouse local -q "SELECT * FROM file('data/data.parquet') LIMIT 10"
```

## Requirements

- `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`) — invoke as `clickhouse local`.

Numbers (timings, sample rows) vary by machine. Reference run: Apple M4 Pro, 14 cores, 24 GB RAM, clickhouse local 26.6.1.117.
