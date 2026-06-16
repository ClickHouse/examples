# Convert CSV to JSONL with clickhouse-local

Runnable companion to
[How to convert CSV to JSONL](https://clickhouse.com/resources/engineering/convert-csv-to-jsonl).

Convert a CSV to JSONL (one JSON object per line) in one command — schema
auto-inferred, types carried into the JSON, no upload, no server.

```bash
./generate.sh   # writes events.csv (20 rows) + events_large.csv (~120 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: the conversion, the inferred schema, reading the JSONL
back, quoting 64-bit integers for JS-safety, convert-and-gzip in one step,
the reverse direction (JSONL -> CSV), and a best-of-3 throughput number on the
3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? Run `run.py` or `run.ipynb` for the chDB version (`pip install chdb`).
