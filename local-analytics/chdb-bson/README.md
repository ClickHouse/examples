# Read a BSON file in Python with chDB

Companion to the article
[How to read a BSON file in Python](https://clickhouse.com/resources/engineering/read-bson-file-python).

Read a `.bson` export (the kind `mongoexport --type=bson` / `mongodump` produces)
into a DataFrame and work with it using the pandas API — no MongoDB server, no
document-by-document decode loop.

## Run it

```bash
./generate.sh        # writes data/ (small flat .bson, nested .bson, a 2M-row .bson)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Requirements: `pip install chdb pandas`, plus `pip install pymongo` for the
perf contrast (`bson.decode_file_iter`), and `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
from chdb.datastore import DataStore
df = DataStore.from_file("data/events.bson", format="BSONEachRow")
```

## What's covered

- `DataStore.from_file(..., format="BSONEachRow")` reads the BSON and infers each field's type automatically.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: chDB DataStore vs the pymongo `decode_file_iter` + pandas path, on a 2M-row file.

## Files

| File | What it is |
|---|---|
| `data/events.bson` | small flat collection (the core read/aggregate examples) |
| `data/orders.bson` | a collection with a nested sub-document |
| `data/events_large.bson` | 2M rows (~149 MB) for the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Perf numbers: Apple M4 Pro, 14 cores, 24 GB RAM, macOS; chDB 4.1.8, Python 3.14; best-of-3, warm.
