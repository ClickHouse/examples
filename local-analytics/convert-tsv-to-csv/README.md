# Convert TSV to CSV with clickhouse-local

Runnable companion to
[How to convert TSV to CSV](https://clickhouse.com/resources/engineering/convert-tsv-to-csv).

Convert a tab-separated file to comma-separated in one line — header carried
over, types inferred, no upload.

```bash
./generate.sh   # writes events.tsv (20 rows) and events_large.tsv (~106 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
```

Covered in `run.sh`: header carry-over via `CSVWithNames`, schema round-trip
check with `DESCRIBE`, header-less output with plain `CSV`, projecting/renaming
columns during conversion, a row-count sanity check, and a best-of-3 perf number
on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the same conversion with chDB
(`pip install chdb`).
