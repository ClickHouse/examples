# Read a TSV file in Python with chDB (drop-in pandas)

Companion to the article
[How to read a TSV file in Python (faster than pandas)](https://clickhouse.com/resources/engineering/read-tsv-file-python).

chDB is a drop-in replacement for pandas: change one import line and your
existing pandas code runs on ClickHouse's engine, so it stays fast as files grow.

## Run it

```bash
./generate.sh        # writes data/ (a small TSV with header, a headerless TSV, a 3M-row TSV)
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
df = pd.read_csv("data/events.tsv", sep="\t")
```

## What's covered

- `pd.read_csv(..., sep="\t")` reads the header and infers each column's type automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- Headerless TSV: pass `names=[...]` to name the columns yourself.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: the same code with one import swapped, on a 3M-row TSV.

## Files

| File | What it is |
|---|---|
| `data/events.tsv` | small TSV with a header row (note the comma inside a value) |
| `data/events_noheader.tsv` | the same rows, no header |
| `data/events_large.tsv` | 3M rows (~85 MB) for the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Prefer the command line? See the `clickhouse local` version,
[Query a TSV file](https://clickhouse.com/resources/engineering/query-a-tsv-file).

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm.
