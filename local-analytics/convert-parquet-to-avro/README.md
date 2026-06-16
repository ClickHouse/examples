# Convert Parquet to Avro with clickhouse-local

Runnable companion to
[How to convert Parquet to Avro](https://clickhouse.com/resources/engineering/convert-parquet-to-avro).

Convert a columnar Parquet file to row-oriented Avro with one command — schema
inferred from the Parquet types, no server, no upload.

```bash
./generate.sh   # writes events.parquet (20 rows) + events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.avro' FORMAT Avro"
```

Covered in `run.sh`: the conversion, the source vs. converted schema (the
unsigned-to-signed integer widening Avro forces), the nested tuple round-tripping
as a nested Avro record, the `deflate` codec, and a best-of-3 perf number on the
3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
