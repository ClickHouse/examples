# Read an Avro file with clickhouse-local

Runnable companion to
[How to read an Avro file](https://clickhouse.com/resources/engineering/read-avro-file).

Query an Avro file directly with SQL. Avro embeds its own schema, so there is
nothing to declare — `DESCRIBE` reads it and logical types (date, timestamp)
come back typed.

```bash
./generate.sh   # writes events.avro (20 rows) + events_large.avro (3M rows, ~61 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.avro') LIMIT 10"
```

Covered in `run.sh`: reading rows, `DESCRIBE` against the embedded schema,
filter/group-by on the Avro file, the date/timestamp logical-type round-trip,
and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: [read an Avro file in Python](https://clickhouse.com/resources/engineering/read-avro-file-python).
