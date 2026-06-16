# Query an NDJSON file with SQL using clickhouse-local

Runnable companion to
[How to query an NDJSON file with SQL](https://clickhouse.com/resources/engineering/query-ndjson-file).

NDJSON (newline-delimited JSON, also called JSON Lines / JSONL) is one JSON
object per line, no enclosing array. `clickhouse local` reads it with the
`JSONEachRow` format and infers the schema, so you query it straight away.

```bash
./generate.sh   # writes events.ndjson (20 rows), events.ndjson.gz, events_large.ndjson (~360 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.ndjson') LIMIT 5"
```

Covered in `run.sh`: `.ndjson` -> `JSONEachRow` auto-detection, `DESCRIBE`,
group-by on the file, the `.jsonl` extension with an explicit format, transparent
`.ndjson.gz` reads, NDJSON -> Parquet conversion, and a best-of-3 perf number on
the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-read-ndjson`.
