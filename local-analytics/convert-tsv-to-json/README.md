# Convert TSV to JSON with clickhouse-local

Runnable companion to
[How to convert TSV to JSON](https://clickhouse.com/resources/engineering/convert-tsv-to-json).

Convert a TSV file to JSON with one command — header and types auto-detected, no upload, no server.

```bash
./generate.sh   # writes events.tsv (20 rows) and events_large.tsv (~105 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: TSV header + type inference, JSONEachRow (NDJSON) vs a single
JSON array (`output_format_json_array_of_rows`), transform-on-export, nesting flat
columns into a JSON object, gzipped JSON output, and a best-of-3 conversion-throughput
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the chDB version (`pip install chdb`).
