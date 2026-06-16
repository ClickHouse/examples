# Query a compressed file with clickhouse-local

Runnable companion to
[How to query a compressed file](https://clickhouse.com/resources/engineering/query-compressed-file).

A `.gz`, `.zst`, `.lz4`, `.br` or `.xz` suffix is auto-detected and decompressed
on the fly. No flag, no decompress step. Parquet's internal codec is read from
the file metadata the same way.

```bash
./generate.sh   # writes events.csv.gz, events.csv.zst, events.zstd.parquet,
                # events.parquet, and events_large.csv.gz (~49 MiB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv.gz') LIMIT 5"
```

Covered in `run.sh`: transparent `.csv.gz` reads, type inference through the
gzip, `.csv.zst`, zstd-compressed Parquet, forcing the codec via the 4th
argument of `file()` when the extension is opaque, aggregation on the
compressed file, and a best-of-3 perf number on the 3M-row gzipped CSV.

Requirements: `clickhouse` (install with `clickhousectl`:
`curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`),
invoked as `clickhouse local`.

Override row counts for a fast verifier run:
`SMALL_ROWS=20 LARGE_ROWS=200000 ./generate.sh`.
