# Query a BSON file with clickhouse-local

Runnable companion to
[How to query a BSON file](https://clickhouse.com/resources/engineering/query-bson-file).

Query a BSON file (MongoDB's binary JSON, what `mongoexport` produces) directly
with SQL — the schema, including nested sub-documents, is auto-detected.

```bash
./generate.sh   # writes events.bson (20 rows) and events_large.bson (~140 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.bson') LIMIT 10"
```

Covered in `run.sh`: BSON schema inference, `DESCRIBE`, reaching into a nested
`geo` sub-document by key (`geo.country`), group-by on the BSON, BSON -> Parquet
conversion, and a best-of-3 perf number on the 1.3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Override the row counts for a fast verifier run: `SMALL_ROWS=10 LARGE_ROWS=50000 ./generate.sh`.
