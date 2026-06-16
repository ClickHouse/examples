# Read a ClickHouse Native format file with clickhouse-local

Runnable companion to
[How to read a ClickHouse Native format file](https://clickhouse.com/resources/engineering/read-clickhouse-native-file).

Native is ClickHouse's own binary columnar format — the same bytes it uses on
the wire and for dumps. It is fully self-describing, so reads need no schema and
the exact types come back unchanged.

```bash
./generate.sh   # writes events.native (20 rows), events.native.gz, events_large.native (3M, ~78 MB), events.csv
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.native') LIMIT 5"
```

Covered in `run.sh`: reading with no schema, `DESCRIBE` showing the exact stored
types (vs the guessed `Nullable` types CSV infers), group-by on the Native file,
piping Native between two processes (`--input-format Native ... FROM table`),
transparent `.native.gz` reads, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? chDB runs the same SQL in-process: `import chdb; chdb.query("SELECT * FROM file('events.native')", "DataFrame")`.
