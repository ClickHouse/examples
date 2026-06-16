# Read a CSV file in Python with chDB (drop-in pandas)

Companion to the article
[How to read a CSV file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-csv-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/ (a small CSV with header, a headerless CSV, a 3M-row CSV)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Row counts are overridable for a fast verify: `SMALL_ROWS=8 LARGE_ROWS=200000 ./generate.sh`.

Requirements: `pip install chdb pandas`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
import chdb.datastore as pd
df = pd.read_csv("data/orders.csv")
```

## What's covered

- `pd.read_csv` reads the header and infers each column's type automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- Headerless CSV: pass `names=[...]` to name the columns yourself.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same code with one import swapped, on a 3M-row CSV.

## Files

| File | What it is |
|---|---|
| `data/orders.csv` | small CSV with a header row |
| `data/orders_noheader.csv` | the same rows, no header |
| `data/orders_large.csv` | 3M rows (~110 MB) for the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Prefer the command line? See the `clickhouse local` version,
[Run SQL on a CSV file](https://clickhouse.com/resources/engineering/run-sql-on-csv-file).

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
