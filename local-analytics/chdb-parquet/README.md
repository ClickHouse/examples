# Read a Parquet file in Python with chDB (drop-in pandas)

Companion to the article
[How to read a Parquet file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-parquet-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/ (a 20M-row Parquet file, ~260 MB)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Requirements: `pip install chdb pandas pyarrow`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_parquet("data/events.parquet")
```

## What's covered

- `pd.read_parquet` reads the Parquet metadata and infers each column's type automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same code with one import swapped, on a 20M-row Parquet file.

## Files

| File | What it is |
|---|---|
| `data/events.parquet` | 20M-row event log (~260 MB) for all examples and the perf contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Prefer the command line? See the `clickhouse-local` version,
[How to query a Parquet file](https://clickhouse.com/resources/engineering/how-to-query-parquet-file).

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
