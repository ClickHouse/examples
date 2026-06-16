# Convert BSON to CSV with clickhouse-local

Runnable companion to
[Convert BSON to CSV](https://clickhouse.com/resources/engineering/convert-bson-to-csv).

Convert a BSON file (the binary JSON MongoDB emits) to CSV with one command. No
upload, no server. Nested sub-documents need flattening — that is the gotcha
this example covers.

```bash
./generate.sh   # writes events.bson (20 rows) and events_large.bson (~145 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.bson') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

A nested BSON sub-document is read as a `Map` and collapses into one quoted CSV
cell. Flatten it into real columns by selecting the keys:

```bash
clickhouse local -q "
SELECT event_id, event_type, geo['city'] AS city, geo['country'] AS country, amount
FROM file('events.bson') INTO OUTFILE 'events_flat.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: the naive one-liner, the inferred schema (`DESCRIBE`), the
nested-document gotcha, flattening into typed columns, and a best-of-3 perf
number on the 1.4M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the same conversion with chDB
(`pip install chdb`).
