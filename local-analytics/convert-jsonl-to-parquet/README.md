# Convert JSONL to Parquet with clickhouse-local

Runnable companion to
[How to convert JSONL to Parquet](https://clickhouse.com/resources/engineering/convert-jsonl-to-parquet).

Convert a JSONL (`JSONEachRow`) file to Parquet in one command — types inferred
per column, nested objects kept as real Parquet structs, no upload.

```bash
./generate.sh   # writes events.jsonl (20 rows) + events_large.jsonl (~137 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: schema inference from JSONL, the types carried into Parquet
(`DateTime64`, a nested `device` object as a `Tuple`/struct), choosing the
compression codec, reading the Parquet footer with `ParquetMetadata`, and a
best-of-3 conversion timing on the ~137 MB file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
