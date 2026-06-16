# Read a RowBinary file with clickhouse-local

Runnable companion to
[How to read a RowBinary file](https://clickhouse.com/resources/engineering/read-rowbinary-file).

Query ClickHouse's `RowBinary` family directly with SQL. `RowBinaryWithNamesAndTypes`
is self-describing; plain `RowBinary` needs an explicit structure.

```bash
./generate.sh   # writes events.rowbinary, events_plain.rowbinary, events_large.rowbinary (~80 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (self-describing variant):

```bash
clickhouse local -q "SELECT * FROM file('events.rowbinary', 'RowBinaryWithNamesAndTypes') LIMIT 10"
```

Covered in `run.sh`: reading the self-describing variant, `DESCRIBE` without
`CREATE TABLE`, group-by on the file, why plain `RowBinary` can't infer a schema,
supplying the structure by hand, the type-validation safety net, and a best-of-3
perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.
