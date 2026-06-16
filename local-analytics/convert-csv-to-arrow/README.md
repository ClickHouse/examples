# Convert CSV to Arrow with clickhouse-local

Runnable companion to
[How to convert CSV to Arrow](https://clickhouse.com/resources/engineering/convert-csv-to-arrow).

Convert a CSV to the Arrow IPC format in one command — schema inferred from the
CSV, types embedded in the Arrow file. No server, no upload.

```bash
./generate.sh   # writes events.csv (20 rows) and events_large.csv (~120 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.arrow' FORMAT Arrow"
```

Covered in `run.sh`: the conversion, the inferred-vs-embedded schema (`Date` ->
`Date32` on readback), the `.feather` alias, zstd compression of the Arrow
buffers, querying the Arrow file directly, and a best-of-3 conversion-throughput
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
