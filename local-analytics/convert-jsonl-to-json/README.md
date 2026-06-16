# Convert JSONL to JSON with clickhouse-local

Runnable companion to
[How to convert JSONL to JSON](https://clickhouse.com/resources/engineering/convert-jsonl-to-json).

Turn line-delimited JSON (one object per line) into a single JSON array — no server, no upload, types preserved.

```bash
./generate.sh   # writes events.jsonl (5 rows) and events_large.jsonl (3,000,000 rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.json' FORMAT JSONEachRow SETTINGS output_format_json_array_of_rows = 1"
```

Covered in `run.sh`: JSONL -> pure JSON array, schema inference, the `FORMAT JSON`
envelope alternative, a round-trip read, and a best-of-3 conversion-throughput
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB (`pip install chdb`).
