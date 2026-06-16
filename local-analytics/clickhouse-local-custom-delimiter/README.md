# Read a file with a custom delimiter with clickhouse-local

Runnable companion to
[How to read a file with a custom delimiter](https://clickhouse.com/resources/engineering/read-custom-delimiter-file).

Query a file whose fields (and rows) use an arbitrary separator, with SQL, no import step.
The `CustomSeparated` family plus two settings handle delimiters that CSV/TSV can't.

```bash
./generate.sh   # writes orders.txt (|~| delimited), orders.txt.gz, orders_pipe.txt, orders_large.txt (~112 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "
SELECT * FROM file('orders.txt', CustomSeparatedWithNames) LIMIT 5
SETTINGS format_custom_field_delimiter='|~|', format_custom_escaping_rule='CSV'"
```

Covered in `run.sh`: a `|~|` field delimiter with auto-detected header, `DESCRIBE`,
group-by on the file, a custom field *and* row delimiter with no header, transparent
`.gz` reads, and a best-of-3 perf number on the 3,000,000-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh`
then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer CLI vs Python? This is the CLI version. For pandas-style work see the chDB pieces in this repo.
