# Read a Feather file with clickhouse-local

Runnable companion to
[How to read a Feather file](https://clickhouse.com/resources/engineering/read-feather-file).

Feather IS the Arrow IPC file format. Read a `.feather` with `FORMAT Arrow`,
no server and no import step.

```bash
./generate.sh   # writes events.feather (20 rows), events_v1.feather (legacy), events_large.feather (~77 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.feather')"
```

Covered in `run.sh`: extension auto-detection, `DESCRIBE`, explicit `FORMAT Arrow`,
group-by on the file, the legacy Feather V1 vs V2 gotcha, Feather -> Parquet
conversion, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. The optional legacy V1 sample uses `pyarrow`.

Prefer Python? See the chDB version: [read a Feather file in Python](https://clickhouse.com/resources/engineering/read-feather-file-python).
