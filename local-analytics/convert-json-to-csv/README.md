# Convert JSON to CSV with clickhouse-local

Runnable companion to
[How to convert JSON to CSV](https://clickhouse.com/resources/engineering/convert-json-to-csv).

Convert newline-delimited JSON to CSV with one command. CSV is flat, so nested
objects and arrays are flattened into named columns first.

```bash
./generate.sh   # writes events.jsonl (20 rows) + events_large.jsonl (~125 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT event_id, event_type, ts, user.country AS user_country, user.plan AS user_plan, amounts[1] AS amount_primary FROM file('events.jsonl', JSONEachRow) INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: schema inference (nested Tuple + Array), why a naive
`SELECT *` produces a misaligned CSV, the explicit flattening projection,
reading the CSV back, the chDB Python equivalent (`run.py` / `run.ipynb`), and a
best-of-3 conversion-throughput number on the 1M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. The Python path needs `chdb` (`pip install chdb`).

Prefer Python? See `run.py` and `run.ipynb` in this folder for the chDB version.
