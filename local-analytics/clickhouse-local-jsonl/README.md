# Run SQL on a JSONL file with clickhouse-local

Runnable companion to
[How to run SQL on a JSONL file](https://clickhouse.com/resources/engineering/run-sql-on-jsonl-file).

Query a JSONL file (one JSON object per line) directly with SQL — keys become
columns and types are inferred, no import step.

```bash
./generate.sh   # writes events.jsonl (20 rows), events.jsonl.gz, events_large.jsonl (~342 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') LIMIT 5"
```

Covered in `run.sh`: JSONEachRow reads, `DESCRIBE`, filter + group-by on the
JSONL, the `.ndjson`/`.json` extension equivalence, transparent `.jsonl.gz`
reads, JSONL -> Parquet conversion, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: [read a JSONL file in Python](https://clickhouse.com/resources/engineering/read-jsonl-file-python).
