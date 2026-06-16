# Convert Parquet to CSV with clickhouse-local

Runnable companion to
[How to convert Parquet to CSV](https://clickhouse.com/resources/engineering/convert-parquet-to-csv).

One command: read the Parquet, write CSV. Schema comes from the Parquet footer,
no upload, streams files larger than RAM.

```bash
./generate.sh   # writes events.parquet (20 rows) and events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: one-line conversion with header, schema from the footer,
row-count round-trip, the nested-column-to-flat-CSV gotcha (and how to flatten a
`Map` into real columns), custom delimiter, headerless output, and a best-of-3
perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB (`pip install chdb`).
