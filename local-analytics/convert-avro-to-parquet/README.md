# Convert Avro to Parquet with clickhouse-local

Runnable companion to
[How to convert Avro to Parquet](https://clickhouse.com/resources/engineering/convert-avro-to-parquet).

One line, no server, no upload. Avro carries its own schema, so the types flow
straight into Parquet.

```bash
./generate.sh   # writes data/events.avro (20 rows) + data/events_large.avro (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: the conversion, the schema Avro carried into Parquet,
reading it back, choosing the compression codec, inspecting the Parquet footer,
and a best-of-3 conversion-throughput number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
