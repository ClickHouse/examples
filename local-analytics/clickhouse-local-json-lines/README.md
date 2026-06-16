# Query a JSON Lines file with clickhouse-local

Runnable companion to
[How to query a JSON Lines file](https://clickhouse.com/resources/engineering/query-json-lines-file).

Query a JSON Lines file (JSONL / NDJSON — one JSON object per line) directly with
SQL. Schema inferred, no import step.

```bash
./generate.sh   # writes events.jsonl (20 rows), events.jsonl.gz, events_large.jsonl (~360 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') LIMIT 5"
```

Covered in `run.sh`: format detection from `.jsonl`, `DESCRIBE` schema inference,
group-by on the file, the JSONL = NDJSON = JSON Lines equivalence (`.ndjson` maps
the same way), naming the format for odd extensions, reading a single top-level
JSON array via `JSONEachRow`, transparent `.jsonl.gz` reads, and a best-of-3 perf
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: [read a JSONL file in Python](https://clickhouse.com/resources/engineering/read-jsonl-file-python).
