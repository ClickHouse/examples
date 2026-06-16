# Convert CSV to NDJSON with clickhouse-local

Runnable companion to
[How to convert CSV to NDJSON](https://clickhouse.com/resources/engineering/convert-csv-to-ndjson).

Convert a CSV to NDJSON (newline-delimited JSON, a.k.a. JSONL) in one command —
schema auto-detected, types carried into the JSON, no upload and no server.

```bash
./generate.sh   # writes events.csv (20 rows) + events_large.csv (~123 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.ndjson' FORMAT JSONEachRow"
```

NDJSON and JSONL are the same format (one JSON object per line); ClickHouse
writes both with `FORMAT JSONEachRow`. Use whichever extension your downstream
tool expects.

Covered in `run.sh`: the one-line conversion, inspecting the output, the
inferred schema, reading the NDJSON straight back, forcing string columns when
inference would guess wrong, and a best-of-3 throughput number on the ~123 MB
file.

Prefer Python? `run.py` (and `run.ipynb`) do the same with chDB:

```python
import chdb
out = chdb.query("SELECT * FROM file('events.csv') FORMAT JSONEachRow").bytes()
open("events.ndjson", "wb").write(out)
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. For the Python path: `pip install chdb`.
