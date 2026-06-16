# Read an Arrow file in Python with chDB (drop-in pandas)

Companion to the article
[How to read an Arrow file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-arrow-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/events.arrow (3M rows, ~69 MB)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Run faster with a smaller file: `LARGE_ROWS=100000 ./generate.sh`.

Requirements: `pip install chdb pandas pyarrow`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_feather("data/events.arrow")
```

Arrow IPC files (`.arrow`) are read by `read_feather` — the Arrow IPC file format and
the Feather format are the same on-disk layout. ClickHouse writes its `Arrow` output
as the IPC file format, so `read_feather` is the right reader.

## What's covered

- `pd.read_feather` reads the Arrow IPC file and infers each column's type from the embedded schema.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `count`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same filter+aggregate with `import chdb.datastore as pd` vs `pyarrow.feather + pandas`, on a 3M-row Arrow file.

## Files

| File | What it is |
|---|---|
| `data/events.arrow` | 3M rows (~69 MB) Arrow IPC file for both examples and the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
