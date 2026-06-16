# Convert Parquet to Arrow with clickhouse-local

Runnable companion to
[How to convert Parquet to Arrow](https://clickhouse.com/resources/engineering/convert-parquet-to-arrow).

Convert a Parquet file to Arrow IPC (Feather) directly with SQL — types carried
across, no upload, no server, streams files larger than RAM.

```bash
./generate.sh   # writes events.parquet (20 rows) and events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.arrow' FORMAT Arrow"
```

Covered in `run.sh`: the conversion, schema parity (Parquet types -> Arrow),
reading the result back, `.feather` as the same Arrow IPC format, zstd
compression of the Arrow output, row/value parity, and a best-of-3 conversion
throughput number on the 3M-row file.

Prefer Python? `run.py` (and `run.ipynb`) do the same conversion in-process with
chDB. See [how to read an Arrow file in Python with chDB](https://clickhouse.com/resources/engineering/read-arrow-file-python).

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. For the Python path: `pip install chdb`.
