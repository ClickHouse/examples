# Parse url-encoded form data with SQL (clickhouse-local)

Runnable companion to
[Parse url-encoded / form data with SQL](https://clickhouse.com/resources/engineering/parse-form-urlencoded).

A `Form`-format file is one `application/x-www-form-urlencoded` body —
`a=1&b=hello&c=...` — and ClickHouse parses it into ONE row with columns `a`, `b`, `c`.
Handy for webhook captures and saved form posts.

```bash
./generate.sh   # writes data/payload.txt, data/encoded.txt, data/hooks/*.txt, data/perf/*.txt (2000 bodies)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('payload.txt', Form)"
```

Covered in `run.sh`: parse one body to a row, `DESCRIBE` (everything is `String`),
applying real types, the percent-encoding / `+`-is-not-a-space gotcha, globbing a
folder of webhook bodies (one row per file) with `_file`, aggregating across them,
and a best-of-3 perf number over 2000 form files.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Override the perf file count for a fast verifier run: `PERF_FILES=200 ./generate.sh`.
