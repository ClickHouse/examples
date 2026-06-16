# Run SQL across multiple CSV/Parquet files with clickhouse-local

Runnable companion to
[Run SQL across multiple CSV or Parquet files](https://clickhouse.com/resources/engineering/run-sql-across-multiple-files).

Glob a directory, read every file as one table, aggregate across all of them in
one query, and attribute each row to its source file with the `_file` virtual
column. No import step.

```bash
./generate.sh   # writes data/sales/*.csv (4), data/events/*.parquet (4), data/sales_large/*.csv (12, ~123 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT _file, count() FROM file('sales/*.csv') GROUP BY _file"
```

Covered in `run.sh`: CSV glob, aggregate across all files, the `_file` and
`_path` virtual columns, the same pattern on a directory of Parquet parts,
brace/range globs to pick a subset, and a best-of-3 perf number on 12 CSVs /
3,000,000 rows.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Override row counts for a fast verify: `SMALL_ROWS=10 LARGE_ROWS=120000 ./generate.sh`.

Prefer Python? Run the same SQL in-process with chDB: see
[what is chDB](https://clickhouse.com/resources/engineering/what-is-chdb).
