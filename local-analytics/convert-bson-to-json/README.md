# Convert BSON to JSON with clickhouse-local

Runnable companion to
[How to convert BSON to JSON](https://clickhouse.com/resources/engineering/convert-bson-to-json).

Convert a BSON file (a MongoDB `mongodump` / `mongoexport --type=bson` dump)
to JSON with one command. Schema auto-inferred, no upload, no server.

```bash
./generate.sh   # writes users.bson (6 docs, nested) + events.bson (~162 MB) into ./data/
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('users.bson') INTO OUTFILE 'users.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: BSON -> NDJSON, the inferred schema, BSON -> a single pretty
JSON array, filtering/flattening while converting, and a best-of-3 perf number
on the 2,000,000-doc file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
