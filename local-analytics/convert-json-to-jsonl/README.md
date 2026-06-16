# Convert JSON to JSONL with clickhouse-local

Runnable companion to
[How to convert JSON to JSONL](https://clickhouse.com/resources/engineering/convert-json-to-jsonl).

Turn a top-level JSON array into JSONL (one object per line) — no upload, schema
auto-inferred, nested fields preserved.

```bash
./generate.sh   # writes events.json (8-element array) + events_large.json (~226 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.json', JSONEachRow) INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
```

`JSONEachRow` reads a top-level `[ {...}, {...} ]` array and emits one object per
line. Covered in `run.sh`: schema inference, line-count check, filter/reshape
during conversion, gzipped JSONL output, and a best-of-3 perf number on the 2M-
element file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the same conversion with
[chDB](https://clickhouse.com/resources/engineering/what-is-chdb)
(`pip install chdb`).
