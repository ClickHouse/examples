# Analyze log files with SQL (clickhouse-local)

Runnable companion to
[How to analyze log files with SQL](https://clickhouse.com/resources/engineering/analyze-log-files-with-sql).

Query raw nginx access logs in place with `clickhouse local` — no Splunk, no
pipeline, no import step. One binary on the box.

## Run it

```bash
./generate.sh          # writes access.log (50k lines) + logs/*.log.gz (rotated, gzipped)
./run.sh               # runs every query from the article
./generate.sh --big    # also writes big_access.log (20M lines, ~2.4 GB) for the perf section
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`),
invoked as `clickhouse local`.

## What it does

- reads raw lines with the `LineAsString` format;
- extracts nginx "combined" fields with `extractGroups()` + `parseDateTime()`;
- status-code counts, p95/p99 latency (`quantile`), top URLs, top error IPs;
- requests-per-minute with `toStartOfMinute`;
- globs over rotated, gzip-compressed logs (`file('logs/*.log.gz', ...)`) — gzip is
  decompressed transparently.

All data is generated locally by `clickhouse local`; nothing large is committed
(see `.gitignore`). `expected_output.txt` shows the real output.

## Perf

Parsing + aggregating the 20M-line / 2.4 GB `big_access.log` (status counts + p95)
ran in ~1.80s best-of-3, warm, on an Apple M4 Pro (14 cores, 24 GB RAM).
