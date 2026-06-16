# Convert Arrow to Parquet with clickhouse-local

Runnable companion to
[How to convert Arrow to Parquet](https://clickhouse.com/resources/engineering/convert-arrow-to-parquet).

Convert Arrow IPC to Parquet with one command. Types are carried straight
across, nothing is uploaded, and files larger than RAM stream through.

```bash
./generate.sh   # writes events.arrow (20 rows), events_stream.arrow, events_large.arrow (~46 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: the one-line conversion, type carry-over (`DESCRIBE` on both
sides), the Arrow IPC **file vs streaming** gotcha (`ArrowStream`), reading the
Parquet footer with `ParquetMetadata`, picking a codec, and a best-of-3 conversion
throughput number on the ~46 MB / 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version in `run.py` / `run.ipynb` (`pip install chdb`).
