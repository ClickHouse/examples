# Flatten nested JSON in Python with chDB (drop-in pandas)

Companion to the article
[How to flatten nested JSON in Python](https://clickhouse.com/resources/engineering/flatten-nested-json-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/ (small nested orders.json + a ~163 MB file for the perf contrast)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Row counts are overridable for a fast verify: `LARGE_ROWS=200000 ./generate.sh`.

Requirements: `pip install chdb pandas`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_json("data/orders.json")
flat = df.explode("items")
```

## What's covered

- `pd.read_json` reads JSON with nested objects and arrays into a lazy, ClickHouse-backed DataFrame.
- `.explode("items")` unrolls the array-of-objects column to one row per element.
- `.to_pandas()` gives a real pandas DataFrame where nested fields are Python dicts.
- Extract nested fields with `.apply(lambda c: c["country"])` — the standard pandas idiom.
- Perf contrast: chDB read + explode + extract vs pandas `json_normalize` on 800k orders.

## Files

| File | What it is |
|---|---|
| `data/orders.json` | small nested JSON array: order -> customer object + array of line-item objects |
| `data/orders_large.json` | 800k orders (~163 MB) for the performance contrast |
| `data/orders.ndjson` | NDJSON source (same data, used by `generate.sh`) |
| `data/orders_large.ndjson` | large NDJSON source (used by `generate.sh`) |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm.
