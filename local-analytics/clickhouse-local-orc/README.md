# Read an ORC file with clickhouse-local

Runnable companion to
[How to read an ORC file](https://clickhouse.com/resources/engineering/read-orc-file).

Query an ORC file directly with SQL — schema auto-detected from the footer, no import step.

```bash
./generate.sh   # writes events.orc (20 rows), events_large.orc (~28 MB, 3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.orc') LIMIT 10"
```

Covered in `run.sh`: schema inference, `DESCRIBE`, group-by on the ORC file,
columnar (stripe) reads of a column subset, overriding the inferred structure,
transparent `.orc.gz` reads, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: [Read an ORC file in Python](https://clickhouse.com/resources/engineering/read-orc-file-python).
