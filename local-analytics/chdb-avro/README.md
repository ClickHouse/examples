# Read an Avro file in Python with chDB (drop-in pandas)

Companion to the article
[How to read an Avro file in Python](https://clickhouse.com/resources/engineering/read-avro-file-python).

chDB lets you read an Avro file into a DataFrame and work with it using the pandas
API you already know, running on ClickHouse's engine. The embedded Avro schema is
read for you — no struct declarations, no record-by-record reader loop.

## Run it

```bash
./generate.sh        # writes data/ (a small Avro file + a 3M-row Avro file)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Requirements: `pip install chdb pandas fastavro`, plus `clickhouse` for
`generate.sh` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh`
then `clickhousectl local use latest`).

## The one-liner

```python
from chdb.datastore import DataStore
df = DataStore.from_file("data/events.avro", format="Avro")
```

## What's covered

- `DataStore.from_file` reads the Avro schema from the file header and infers every column.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: DataStore vs a fastavro reader loop on a 3M-row Avro file.

## Files

| File | What it is |
|---|---|
| `data/events.avro` | small Avro file with a nested `user` record |
| `data/events_large.avro` | 3M rows for the performance contrast |

`expected_output.txt` has the real captured output so the example is self-verifying.

## Codec note

`generate.sh` writes Avro with the `deflate` codec so `fastavro` reads it with no
extra dependencies. ClickHouse defaults to `snappy`, which `fastavro` can read only
if you also `pip install cramjam`. chDB reads either codec out of the box.

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm.
