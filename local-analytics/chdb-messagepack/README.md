# Read a MessagePack file in Python with chDB (drop-in pandas)

Companion to the article
[How to read a MessagePack file in Python](https://clickhouse.com/resources/engineering/read-messagepack-file-python).

Read a `.msgpack` file into a DataFrame and work with it using the pandas API you
already know, running on ClickHouse's engine. MsgPack carries no schema, so you
pass the column list once via `structure=` and the rest is standard pandas.

## Run it

```bash
./generate.sh        # writes data/ (a small .msgpack + a 3M-row file)
python3 run.py       # runs every snippet from the article plus the perf contrast
# or open run.ipynb in Jupyter
```

Requirements: `pip install chdb pandas msgpack`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
from chdb.datastore import DataStore

SCHEMA = "event_id UInt64, country String, event_type String, amount Float64"
df = DataStore.from_file("data/events.msgpack", format="MsgPack", structure=SCHEMA)
```

## The gotcha

MsgPack is schemaless. Unlike Parquet, ORC, or Avro, there are no column names or
types in the file. Omit `structure=` and the read fails with
`CANNOT_EXTRACT_TABLE_STRUCTURE`. Pass the columns in the order the file was written
and everything else is standard pandas.

## What's covered

- `DataStore.from_file` reads the file into a lazy, ClickHouse-backed DataFrame.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- What happens if you forget `structure=` (the error message and the fix).
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Perf contrast: chDB DataStore vs a hand-written `msgpack` decode loop, on a 3M-row file.

## Files

| File | What it is |
|---|---|
| `data/events.msgpack` | small MsgPack file for the worked examples |
| `data/events_large.msgpack` | 3M rows (~74 MB) for the performance contrast |

`expected_output.txt` has the real captured output so the example is self-verifying.

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14,
msgpack 1.1.2; best-of-3, warm.
