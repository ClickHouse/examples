# What is a Parquet file?

Runnable companion to the article
[What is a Parquet file?](https://clickhouse.com/resources/engineering/what-is-parquet-file).

Generates a small demo Parquet file locally, then uses `clickhouse local` to read it
and to surface its internal structure (row groups, column chunks, compression,
per-row-group min/max statistics) straight from the file's own metadata.

## Run it

```bash
./generate.sh   # writes data/events.parquet (2,000,000 rows, 7 columns, 4 row groups)
./run.sh        # reads the file + dumps its Parquet metadata
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

## What's in the file

Synthetic event data: `id`, `event_time` (one row per minute, so it's monotonic),
`country`, `device`, `event_type`, `revenue`, `quantity`. Written with
`output_format_parquet_row_group_size = 500000` so you get 4 row groups to inspect.

## Notes on reproducibility

Structure is deterministic: 2M rows, 7 columns, 4 row groups, the physical types,
compression (ZSTD), per-column ratios, and the non-overlapping `event_time` ranges
per row group are stable across runs. The `revenue` column uses `randUniform`, so the
`sum(revenue)` figures in step 1 vary slightly run-to-run; `expected_output.txt` is a
real capture from one run.
