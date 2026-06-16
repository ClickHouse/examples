# Read a semicolon-separated file with clickhouse-local

Runnable companion to
[How to read a semicolon-separated file](https://clickhouse.com/resources/engineering/read-semicolon-separated-file).

Query a `;`-delimited file (European-style CSV) directly with SQL, no import step.
Treat it as `CustomSeparatedWithNames` with a `;` field delimiter.

```bash
./generate.sh   # writes orders.csv (20 rows, ';'), orders_eu.csv (decimal commas), orders_large.csv (~110 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "
SELECT * FROM file('orders.csv', CustomSeparatedWithNames)
LIMIT 10
SETTINGS format_custom_field_delimiter = ';', format_custom_escaping_rule = 'CSV'"
```

Covered in `run.sh`: header + type inference over `;`, `DESCRIBE`, group-by on
the file, the European decimal-comma gotcha (revenue infers as `String`) and the
`replaceOne(...)::Float64` fix, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? Run the same `file()` query through chDB: `import chdb; chdb.query(sql, "DataFrame")`.
