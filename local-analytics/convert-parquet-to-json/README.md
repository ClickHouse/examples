# Convert Parquet to JSON with clickhouse-local

Runnable companion to
[How to convert Parquet to JSON](https://clickhouse.com/resources/engineering/convert-parquet-to-json).

Convert a Parquet file to JSON in one command — schema read from the Parquet
footer, types and nested columns carried into the JSON. No server, no upload.

```bash
./generate.sh   # writes events.parquet (typed + nested) and events_large.parquet (~3M rows, ~46 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

`JSONEachRow` writes one JSON object per line (NDJSON / JSON Lines). For a
single JSON array with metadata, use `FORMAT JSON` instead.

Covered in `run.sh`: JSONEachRow vs JSON array, the inferred schema, typed +
nested columns (Date, Decimal, `Array`, named `Tuple`) carrying into JSON,
stringifying 64-bit ints for strict parsers, reshaping while converting, and a
best-of-3 conversion-throughput number on the ~3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version in `run.py` / `run.ipynb` (`chdb` 4.x, `pandas`, `pyarrow`).
