# Run SQL on a CSV file with clickhouse-local

Runnable companion to
[How to run SQL on a CSV file](https://clickhouse.com/resources/engineering/run-sql-on-csv-file).

Query a CSV directly with SQL — header and types auto-detected, no import step.

```bash
./generate.sh   # writes orders.csv (20 rows), orders.csv.gz, orders_large.csv (~338 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('orders.csv') LIMIT 10"
```

Covered in `run.sh`: header + type inference, `DESCRIBE`, group-by on the CSV,
overriding the inferred structure, CSV -> Parquet conversion, transparent
`.csv.gz` reads, and a best-of-3 perf number on the 8M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-read-csv`.
