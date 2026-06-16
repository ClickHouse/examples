# Query a mysqldump file with clickhouse-local

Runnable companion to
[How to query a mysqldump file without importing](https://clickhouse.com/resources/engineering/query-mysqldump-file).

Read the `INSERT` statements in a `mysqldump` `.sql` file directly with SQL — no MySQL server, no import step.

```bash
./generate.sh   # writes data/shop.sql (customers + orders) and data/events_large.sql (2M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (pick one table from a multi-table dump):

```bash
clickhouse local -q "
SELECT * FROM file('shop.sql', MySQLDump)
SETTINGS input_format_mysql_dump_table_name = 'orders'"
```

Covered in `run.sh`: listing the tables in a dump, schema inference from the
`CREATE TABLE` DDL, selecting a table with `input_format_mysql_dump_table_name`,
the default-first-table behaviour, group-by directly on the dump, and a
best-of-3 perf number on the 2M-row dump.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Note: `clickhouse local` reads dumps that contain the `LOCK TABLES` / multi-row
`INSERT` layout produced by `mysqldump` (the default). The example data matches that layout.
