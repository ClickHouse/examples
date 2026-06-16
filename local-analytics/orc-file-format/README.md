# ORC file format

Runnable companion to the article
[ORC file format](https://clickhouse.com/resources/engineering/orc-file-format).

Generates a small demo ORC file locally, reads it with `clickhouse local`, and
cracks its footer (stripes, row-index stride, compression, footer/postscript sizes)
with a standard ORC reader to show the format's internal structure.

## Run it

```bash
./generate.sh   # writes data/events.orc (1,000,000 rows, 7 columns, ZSTD)
./run.sh        # describes + reads the file, then dumps its ORC footer
```

Requirements:
- `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.
- Python 3 with `pyarrow` (`pip install pyarrow`) for the footer dump in step 3. ClickHouse reads ORC data natively but has no ORC-metadata `FORMAT`, so a standard ORC reader exposes the footer.

Override the row count for a faster run: `LARGE_ROWS=20000 ./generate.sh`.

## What's in the file

Synthetic event data: `id`, `event_time` (one row per minute, monotonic), `country`,
`device`, `event_type`, `revenue`, `quantity`. Written with the default ZSTD codec and
a 10,000-row index stride.

## Notes on reproducibility

Structure is deterministic: 1M rows, 7 columns, ZSTD, 10k stride, 100 row-index groups,
single stripe. The `revenue` column uses `randUniform`, so the `sum(revenue)` figures in
step 2 vary slightly run-to-run; `expected_output.txt` is a real capture from one run.

Prefer Python? See [read an ORC file in Python](https://clickhouse.com/resources/engineering/read-orc-file-python).
