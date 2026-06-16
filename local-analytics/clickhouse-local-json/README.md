# Query a JSON file with SQL using clickhouse-local

Runnable companion to
[How to query a JSON file with SQL](https://clickhouse.com/resources/engineering/run-sql-on-json-file).

Query JSON directly with SQL — line-delimited (JSONL/NDJSON) or a top-level
array, nested objects via dot access, array columns via `ARRAY JOIN`. No server,
no import step.

```bash
./generate.sh   # writes events.jsonl (20 rows), events.json (array), events.jsonl.gz, events_large.jsonl (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl', JSONEachRow) LIMIT 5"
```

Covered in `run.sh`: reading JSONL and a top-level JSON array with the same
`JSONEachRow` call, schema inference (nested object -> `Tuple`, array ->
`Array`), `DESCRIBE`, dot access into a nested object (`geo.country`), grouping
by a nested field, exploding an array with `ARRAY JOIN`, transparent
`.jsonl.gz` reads, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-read-json`.
