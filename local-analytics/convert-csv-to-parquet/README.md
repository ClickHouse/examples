# Convert CSV to Parquet with clickhouse-local

Runnable companion to
[How to convert CSV to Parquet](https://clickhouse.com/resources/engineering/convert-csv-to-parquet).

One command, no server, no upload. Types are inferred from the CSV and carried
into the Parquet schema; you choose the compression codec and row-group size.

```bash
./generate.sh   # writes orders.csv (20 rows) and orders_large.csv (~132 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.parquet' TRUNCATE FORMAT Parquet"
```

Covered in `run.sh`: the one-line conversion, the inferred Parquet schema,
picking the codec (`output_format_parquet_compression_method`) and row-group
size, overriding types before writing, a zstd-vs-lz4 size comparison on the
~132 MB file, and a best-of-3 conversion-throughput number.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion in-process with
chDB (`pip install chdb`).
