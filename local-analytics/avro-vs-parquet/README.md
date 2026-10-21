# Avro vs Parquet

Write the same 500,000 events to Avro and Parquet, then compare reading two columns with reading all 20. Parquet can skip unneeded columns; Avro reads through the records. This is a runnable companion to [Avro vs Parquet](https://clickhouse.com/resources/engineering/avro-vs-parquet).

## Run it

1. Install [Python 3](https://www.python.org/downloads/) and [clickhousectl](https://clickhouse.com/docs/get-started/setup/self-managed/clickhousectl), then download ClickHouse.

   ```sh
   clickhousectl local install 26.9
   ```

2. From the root of this repository, run the example.

   ```sh
   cd local-analytics/avro-vs-parquet
   python3 demo.py --version 26.9
   ```

The demo selects an installed 26.9 version without changing your CLI default. It generates both files, checks that both formats return the same data, and prints four elapsed times for the two-column and all-column reads. Python's standard library is sufficient.

Each run saves the files, SQL, correctness checks, and `results.csv` in a new folder under `demo-output/`.

These are quick local timings. The [recorded results](reference/cli-26.8.32.16/README.md) and [optional measurement harness](REPRODUCING.md) document the controlled run separately.

## Prompt for your agent

```text
Run local-analytics/avro-vs-parquet locally with clickhousectl and python3 demo.py --version 26.9. Check that both formats match the generated data for two-column and all-column reads. Report the four timings and output folder, keeping the existing reference results unchanged.
```
