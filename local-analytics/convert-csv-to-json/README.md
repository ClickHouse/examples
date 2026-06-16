# Convert CSV to JSON with clickhouse-local

Runnable companion to
[How to convert CSV to JSON](https://clickhouse.com/resources/engineering/convert-csv-to-json).

Convert a CSV to JSON from the terminal — schema auto-inferred, types carried into
the JSON, no upload and no server.

```bash
./generate.sh   # writes orders.csv (20 rows) and orders_large.csv (~84 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (one JSON object per line, NDJSON):

```bash
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.jsonl' FORMAT JSONEachRow"
```

A single JSON array of objects instead:

```bash
clickhouse local -q "SELECT * FROM file('orders.csv') FORMAT JSON" > orders.json
```

Covered in `run.sh`: line-delimited `JSONEachRow`, the `FORMAT JSON` array form,
`JSONCompactEachRow`, how inferred types carry into the JSON, forcing a column to
stay a string, and a best-of-3 conversion throughput number on the ~84 MB file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? The chDB equivalent is in `run.py` / `run.ipynb` (`pip install chdb`).
