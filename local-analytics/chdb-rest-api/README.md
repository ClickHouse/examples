# Query a REST API in Python with chDB (pandas API)

Companion to the article
[How to query a REST API in Python](https://clickhouse.com/resources/engineering/query-rest-api-with-sql-python).

Read a JSON API response into a DataFrame with `DataStore.from_url`, then filter
and aggregate with the pandas API you already know, running on ClickHouse's engine.

## Run it

```bash
./generate.sh        # writes data/ (a small API response, two pages, a 2M-row response)
python3 run.py       # serves data/ over http.server, reads + aggregates + perf contrast
# or open run.ipynb in Jupyter
```

`run.py` and the notebook start a local `http.server` over `data/` so `DataStore.from_url()`
has a real endpoint to hit. The same call works unchanged against any public API that returns JSON.

Requirements: `pip install chdb pandas`, plus `clickhouse` for `generate.sh`
(install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then
`clickhousectl local use latest`).

## The one-liner

```python
from chdb.datastore import DataStore

df = DataStore.from_url("https://api.example.com/orders", format="JSONEachRow")
```

## What's covered

- `DataStore.from_url` reads a JSON HTTP endpoint into a ClickHouse-backed DataFrame; schema is inferred.
- Filter + aggregate with the pandas you already write (`df[...]`, `groupby`, `sum`) — no SQL.
- `df.to_pandas()` returns a real `pandas.DataFrame` when a downstream library needs one.
- Multiple pages: read each URL into a DataFrame, then `pd.concat`.
- Perf contrast: `DataStore.from_url` vs `urllib` + `json` + manual aggregation loop.

## Files

| File | What it is |
|---|---|
| `data/orders.json` | small "GET /orders" response (JSON-lines, nested labels field) |
| `data/orders_page1.json`, `orders_page2.json` | two pages of the same endpoint |
| `data/orders_large.json` | 2M rows (~120 MB) for the performance contrast |

`expected_output.txt` has the real (trimmed) output so the example is self-verifying.

Perf numbers: Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm;
over localhost (network latency removed, isolates parse+aggregate cost).
