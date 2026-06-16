# Read a JSON file in Python with chDB (drop-in pandas)

Companion to the article
[How to read a JSON file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-json-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/ (small NDJSON, a JSON array, a 2M-row NDJSON)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Requirements: `pip install chdb pandas`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_json("data/events.ndjson", lines=True)
```

## What's covered

- `pd.read_json(..., lines=True)` reads NDJSON / json-lines; types are inferred automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- Nested objects come back as struct columns; use `.apply` to extract fields after `.to_pandas()`.
- Nested arrays come back as list columns; use `.explode()` to flatten them.
- A top-level JSON array reads with `pd.read_json("file.json")` (no `lines=True`).
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same code with one import swapped, on a 2M-row NDJSON.

## Files

| File | What it is |
|---|---|
| `data/events.ndjson` | small NDJSON with nested objects + arrays |
| `data/events_array.json` | the same rows as one top-level JSON array |
| `data/events_irregular.ndjson` | rows with differing keys (kept for generate.sh) |
| `data/events_2m.ndjson` | 2M rows (~146 MB) for the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Prefer the command line? See the `clickhouse local` version,
[Run SQL on a JSON file](https://clickhouse.com/resources/engineering/run-sql-on-json-file).

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm.
