# clickhouse-local intro

Runnable companion to **[What is clickhouse-local?](https://clickhouse.com/resources/engineering/what-is-clickhouse-local)**

`clickhouse-local` runs full ClickHouse SQL over local and remote files (and
external databases) from a single binary — no server, no import step.

## Run it

```bash
./generate.sh   # makes a tiny parquet + csv + two log files (one .gz), locally
./run.sh        # version, SELECT, DESCRIBE, glob+gz, CSV->Parquet, JOIN, url()
```

`run.sh` reproduces the exact one-liners from the article. Compare your output
against [`expected_output.txt`](./expected_output.txt).

## Requirements

- `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`) — invoked as `clickhouse local`.
- Step 7 (`url()`) needs network access; it skips gracefully when offline.

Sample data is generated locally by `clickhouse local` itself, so nothing large
is committed to git.
