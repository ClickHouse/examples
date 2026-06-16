# Convert ORC to Parquet with clickhouse-local

Runnable companion to
[How to convert ORC to Parquet](https://clickhouse.com/resources/engineering/convert-orc-to-parquet).

Convert an ORC file to Parquet with one command. No server, no upload — both are
columnar, so the schema (including nested `Map` columns) carries over.

```bash
./generate.sh   # writes events.orc (20 rows) and events_large.orc (3,000,000 rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: the conversion, inferred-schema check on both sides, nested
`Map` preservation, choosing the Parquet compression codec, reading the Parquet
footer with `ParquetMetadata`, and a best-of-3 conversion-throughput number on
the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? The same conversion with chDB is in `run.py` / `run.ipynb`
(`import chdb`; `pip install chdb`).
