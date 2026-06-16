# Convert Parquet to JSONL with clickhouse-local

Runnable companion to
[How to convert Parquet to JSONL](https://clickhouse.com/resources/engineering/convert-parquet-to-jsonl).

Convert a Parquet file to newline-delimited JSON (one object per line) with one
command — schema read from the Parquet footer, types carried into JSON, nested
columns preserved as nested objects. No server, no upload.

```bash
./generate.sh   # writes events.parquet (20 rows) + events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: the conversion, schema/type carry-over, the `Map` column
landing as a nested JSON object, filtering on the way out, gzip on the way out
(`.jsonl.gz`), and a best-of-3 perf number on the 3M-row file.

Prefer Python? `run.py` / `run.ipynb` do the same conversion in chDB
(`import chdb`), in-process, no server.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. For the Python version: `pip install chdb`.
