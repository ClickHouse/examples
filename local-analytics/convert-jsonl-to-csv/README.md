# Convert JSONL to CSV with clickhouse-local

Runnable companion to
[How to convert JSONL to CSV](https://clickhouse.com/resources/engineering/convert-jsonl-to-csv).

Convert line-delimited JSON to CSV in one command — no upload, no server, schema
auto-inferred. Nested objects and arrays are flattened into scalar columns.

```bash
./generate.sh   # writes events.jsonl (12 rows) + events_large.jsonl (~146 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

The gotcha this example covers: `SELECT *` on JSONL with a nested object writes
more CSV columns than the header names, so you flatten with `geo.country` /
`arrayStringConcat(tags, '|')` instead. `run.sh` shows the broken naive convert,
the inferred schema, the correct flattened convert, the read-back, and a
best-of-3 perf number on the 1.2M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the chDB version (`import chdb`),
which runs the identical SQL in-process and writes the identical CSV.
