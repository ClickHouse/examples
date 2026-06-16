# Read a TSV file with clickhouse-local

Runnable companion to
[How to read a TSV file](https://clickhouse.com/resources/engineering/query-a-tsv-file).

Query a tab-separated file directly with SQL — header and types auto-detected, no import step.

```bash
./generate.sh   # writes orders.tsv (20 rows), orders_nohdr.tsv, orders.tsv.gz, orders_large.tsv (~110 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('orders.tsv') LIMIT 10"
```

Covered in `run.sh`: header + type inference with `TSVWithNames`, `DESCRIBE`,
group-by on the TSV, headerless TSV with an explicit schema, transparent
`.tsv.gz` reads, TSV -> CSV conversion, and a best-of-3 perf number on the
3M-row file (which also shows why pinning the schema matters for text formats).

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-tsv`.
