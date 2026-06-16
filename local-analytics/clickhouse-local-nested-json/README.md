# Query nested JSON with SQL using clickhouse-local

Runnable companion to
[How to query nested JSON with SQL](https://clickhouse.com/resources/engineering/query-nested-json-sql).

Query deeply nested JSON directly with SQL: dot access into objects, `ARRAY JOIN`
to explode arrays, and `JSONExtract*` / the `JSON` type for irregular keys. No
server, no schema declaration, no import step.

```bash
./generate.sh   # writes events.jsonl (5 rows), events.jsonl.gz, events_large.jsonl (~137 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT user.geo.country, count() FROM file('events.jsonl') GROUP BY 1"
```

Covered in `run.sh`: nested schema inference (`DESCRIBE`), dot access into nested
objects (`user.geo.country`), exploding a nested array of objects with `ARRAY JOIN`,
pulling irregular keys with `JSONExtractString`/`JSONExtractBool`, the native `JSON`
type for dynamic keys, reading a whole document with `JSONAsObject`, transparent
`.jsonl.gz` reads, and a best-of-3 perf number on the 500k-row file.

Override row counts for a fast verify: `SMALL_ROWS=5 LARGE_ROWS=100000 ./generate.sh`.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version for flattening nested JSON into a DataFrame:
[flatten nested JSON in Python](https://clickhouse.com/resources/engineering/flatten-nested-json-python).
