# Convert NDJSON to CSV with clickhouse-local

Runnable companion to
[How to convert NDJSON to CSV](https://clickhouse.com/resources/engineering/convert-ndjson-to-csv).

Convert line-delimited JSON to CSV with one command — no server, no upload, schema auto-inferred.

```bash
./generate.sh   # writes events.ndjson (20 rows, nested) + events_large.ndjson (~144 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: the naive `SELECT *` flattening trap on nested objects, the
inferred Tuple schema, the correct flatten-and-serialise conversion, a round-trip
read of the result, and a best-of-3 perf number on the 1M-row file.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`import chdb; chdb.query(...)`).

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. For the Python version: `pip install chdb pandas`.
