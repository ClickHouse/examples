# Convert TSV to Parquet with clickhouse-local

Runnable companion to
[How to convert TSV to Parquet](https://clickhouse.com/resources/engineering/convert-tsv-to-parquet).

Convert a tab-separated file to Parquet in one command — schema inferred from the
TSV, types carried into Parquet, zstd compression by default. No upload, no server.

```bash
./generate.sh   # writes events.tsv (20 rows) and events_large.tsv (~111 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: one-line conversion, inferred-vs-locked schema, the codec
comparison (none / lz4 / zstd) on the 3M-row file, `ParquetMetadata` footer
inspection, and a best-of-3 conversion-throughput number.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`pip install chdb`). See [read a TSV file in Python](https://clickhouse.com/resources/engineering/read-tsv-file-python).
