# Read a pipe-delimited file with clickhouse-local

Runnable companion to
[How to read a pipe-delimited file](https://clickhouse.com/resources/engineering/read-pipe-delimited-file).

A pipe-delimited (`|`) file is read with the `CustomSeparated` family plus two
settings: the field delimiter and the per-field escaping rule.

```bash
./generate.sh   # writes orders.psv (20 rows), orders_nohdr.psv, orders_large.psv (~126 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "
SELECT * FROM file('orders.psv', 'CustomSeparatedWithNames') LIMIT 10
SETTINGS format_custom_field_delimiter='|', format_custom_escaping_rule='CSV'"
```

Covered in `run.sh`: header detection with `CustomSeparatedWithNames`, `DESCRIBE`,
the `escaping_rule='CSV'` gotcha (without it, quotes aren't stripped and the row
collapses into one column), group-by, the headerless `CustomSeparated` variant
with an explicit schema, setting the format once with `SET`, transparent
`.psv.gz` reads, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer CLI vs Python? This is the CLI version. The same pipe-delimited read works
from Python with chDB by passing the identical `CustomSeparatedWithNames` + settings to `chdb.query`.
