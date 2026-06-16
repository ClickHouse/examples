# What is an Avro file?

Runnable companion to the article
[What is an Avro file?](https://clickhouse.com/resources/engineering/what-is-an-avro-file).

Generates small demo Avro files locally, then uses `clickhouse local` to read them,
to print the JSON schema that Avro embeds in the file header, and to show schema
evolution (a `v2` file that added a column).

## Run it

```bash
./generate.sh   # writes data/events_v1.avro, data/events_v2.avro, data/events_big.avro
./run.sh        # describes, dumps the embedded schema, queries the files
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. Step 2 also pipes through `python3 -m json.tool` to pretty-print the schema.

Override row counts for a fast verify: `SMALL_ROWS=200 LARGE_ROWS=500000 ./generate.sh`.

## What's in the files

Synthetic event data: `id`, `event_time`, `country`, `revenue`. The `v2` file adds a
`channel` field to the same record, to demonstrate Avro's schema evolution. `events_big.avro`
(3,000,000 rows by default) is used for the throughput number.

## Notes on reproducibility

The schemas, the embedded `avro.schema` JSON in each header, and the column structure are
stable across runs. `revenue` uses `randUniform`, so the `sum(revenue)` figures vary slightly
run-to-run; `expected_output.txt` is a real capture from one run.

Prefer Python? See [Read an Avro file in Python](https://clickhouse.com/resources/engineering/read-avro-file-python).
