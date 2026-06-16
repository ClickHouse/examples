# Read a .npy file in Python with chDB

Companion to the article
[How to read an NPY file in Python](https://clickhouse.com/resources/engineering/read-npy-file-python).

chDB lets you read a `.npy` array into a DataFrame and work with it using the
pandas API you already know, running on ClickHouse's engine. There is no server
to start and no separate load step.

## Run it

```bash
./generate.sh        # writes data/ (.npy arrays via clickhouse local + numpy)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Row counts are overridable for a fast verify: `SMALL_ROWS=8 LARGE_ROWS=100000 ./generate.sh`.

Requirements: `pip install chdb pandas numpy`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
from chdb.datastore import DataStore
df = DataStore.from_file("data/readings.npy", format="Npy")
```

## What's covered

- `DataStore.from_file` reads the array into a lazy, ClickHouse-backed DataFrame object.
- A `.npy` holds one numeric array with no column names; chDB exposes a single column called `array`.
- Filter and aggregate with pandas (`.mean()`, `.max()`, `.min()`, boolean indexing) — no SQL.
- A 2-D `.npy` reads as one row per outer element (each row is an array value).
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Honest perf vs `numpy.load`: NumPy wins the raw vectorized reduction; chDB adds value when you need it in DataFrame form or when you're combining it with other operations.

## Files

| File | What it is |
|---|---|
| `data/readings.npy` | small 1-D Float64 array (sensor readings) |
| `data/flags.npy` | a 1-D UInt8 quality flag, same length as readings |
| `data/matrix.npy` | a 2-D Int64 array (reads as one row per outer element) |
| `data/large.npy`, `data/large_flags.npy` | 3M-row arrays for the perf contrast |

`expected_output.txt` has the real captured output so the example is self-verifying.

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
