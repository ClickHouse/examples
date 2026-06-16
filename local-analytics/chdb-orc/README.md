# Read an ORC file in Python with chDB (drop-in pandas)

Companion to the article
[How to read an ORC file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-orc-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/events.orc (3M rows, ~25 MB)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Row count is overridable for a fast verify: `LARGE_ROWS=100000 ./generate.sh`.

Requirements: `pip install chdb pandas`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_orc("data/events.orc")
```

## What's covered

- `pd.read_orc` reads the ORC footer schema and infers each column's type automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same code with one import swapped, on a 3M-row ORC file.

## Files

| File | What it is |
|---|---|
| `data/events.orc` | 3M-row ORC file for the snippets and perf contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
