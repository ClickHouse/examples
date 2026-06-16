#!/usr/bin/env python3
"""Read a JSON file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-json-file-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd


print("=== 1. Read NDJSON into a DataFrame (types auto-inferred) ===")
df = pd.read_json("data/events.ndjson", lines=True)
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
purchases = (df[df["event_type"] == "purchase"]
             .groupby("country")["revenue"].sum()
             .sort_values(ascending=False))
print(purchases)

print("\n=== 3. Nested objects: extract fields with .apply after .to_pandas() ===")
import pandas as real_pd
pdf = df.to_pandas()
pdf["user_id"] = pdf["user"].apply(lambda x: x[0])
pdf["user_tier"] = pdf["user"].apply(lambda x: x[1])
print(pdf[["event_id", "user_id", "user_tier", "revenue"]])

print("\n=== 4. Nested arrays: flatten with .explode ===")
exploded = (pdf[["event_id", "items"]]
            .explode("items")
            .dropna(subset=["items"])
            .reset_index(drop=True))
print(exploded)

print("\n=== 5. A top-level JSON array reads without lines=True ===")
arr_df = pd.read_json("data/events_array.json")
print(f"rows: {len(arr_df)}")

print("\n=== 6. Hand off to real pandas when you need it ===")
result = df[df["event_type"] == "purchase"].groupby("country")["revenue"].sum()
pdf_result = result.to_pandas()
print(type(pdf_result))
print(pdf_result)

print("\n=== 7. Performance: same code, one import swapped, on a 2M-row NDJSON ===")


def datastore_agg():
    d = pd.read_json("data/events_2m.ndjson", lines=True)
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["revenue"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    import pandas as real_pd2
    p = real_pd2.read_json("data/events_2m.ndjson", lines=True)
    return (p[p["event_type"] == "purchase"]
            .groupby("country")["revenue"].sum()
            .sort_values(ascending=False))


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


pd_s = best_of_3(pandas_agg)
ds_s = best_of_3(datastore_agg)
print(f"import pandas as pd:            {pd_s:.3f}s")
print(f"import chdb.datastore as pd:    {ds_s:.3f}s")
print(f"speedup:                        {pd_s / ds_s:.1f}x")
