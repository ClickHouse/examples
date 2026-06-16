# Convert JSON to Parquet with clickhouse-local

Runnable companion to
[How to convert JSON to Parquet](https://clickhouse.com/resources/engineering/convert-json-to-parquet).

One command, no server, no upload. Schema is inferred from the JSON and the
types are carried into Parquet — including nested objects, which become typed
nested columns.

```bash
./generate.sh   # writes events.json (12 rows) + events_large.json (1,000,000 rows, ~133 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.json') INTO OUTFILE 'events.parquet' TRUNCATE FORMAT Parquet"
```

Covered in `run.sh`: the conversion, the inferred JSON schema, the matching
Parquet schema, how the nested `geo` object maps to nested Parquet columns,
reading the typed columns back, the compression-codec setting, the JSON-vs-Parquet
size difference, and a best-of-3 conversion time on the 1M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`). It writes `events_chdb.parquet` and reads it back into a
pandas DataFrame.
