# Convert ORC to JSON with clickhouse-local

Runnable companion to
[How to convert ORC to JSON](https://clickhouse.com/resources/engineering/convert-orc-to-json).

Convert an ORC file to JSON with one SQL command — schema read from the ORC
footer, nested structs preserved as nested JSON, no upload and no server.

```bash
./generate.sh   # writes events.orc (20 rows) + events_large.orc (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: ORC -> NDJSON (`JSONEachRow`), the carried-over schema via
`DESCRIBE`, ORC -> a single `JSON` array, filtering/flattening during the
convert, lossless 64-bit/Decimal output as quoted strings, and a best-of-3 perf
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? The same conversion with chDB is in `run.py` / `run.ipynb`
(`pip install chdb`).
