# Convert NDJSON to Parquet with clickhouse-local

Runnable companion to
[How to convert NDJSON to Parquet](https://clickhouse.com/resources/engineering/convert-ndjson-to-parquet).

NDJSON and JSONL are the same format (one JSON object per line). Convert it to
Parquet with one command — schema auto-inferred, nested objects and arrays
preserved, no upload and no server.

```bash
./generate.sh   # writes data/events.ndjson (20 rows, nested), events_large.ndjson (~140 MB)
./run.sh        # CLI: every command from the article; compare with expected_output.txt
python3 run.py  # Python (chDB): the same conversion in-process
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.ndjson') INTO OUTFILE 'events.parquet' FORMAT Parquet"
```

Covered in `run.sh`: schema inference, nested object -> Tuple and array -> Array
carried into Parquet, reading the nested columns back, the Parquet footer
(leaf columns + ZSTD), choosing the compression codec, and a best-of-3
conversion-throughput number on the ~140 MB file.

Requirements:
- CLI: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.
- Python: `pip install chdb`.

Prefer CLI? Use `run.sh`. Prefer Python? Use `run.py` / `run.ipynb`.
