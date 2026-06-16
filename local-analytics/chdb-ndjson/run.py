#!/usr/bin/env python3
"""Read an NDJSON file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-ndjson-file-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd


print("=== 1. Read an NDJSON file into a DataFrame (types auto-inferred) ===")
df = pd.read_json("data/events.ndjson", lines=True)
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
purchases = df[df["event_type"] == "purchase"].groupby("country")["revenue"].sum().sort_values(ascending=False)
print(purchases)

print("\n=== 3. Access nested fields with pandas-style indexing ===")
# user column contains dicts; extract fields with str accessor or apply
user_tiers = df[["event_id", "revenue"]].copy().to_pandas()
user_tiers["tier"] = df["user"].to_pandas().apply(lambda u: u["tier"] if isinstance(u, dict) else u[1])
gold = user_tiers[user_tiers["tier"] == "gold"]
print(gold)

print("\n=== 4. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 5. Performance: same code, one import swapped, on a 2M-row NDJSON file ===")


def datastore_agg():
    d = pd.read_json("data/events_large.ndjson", lines=True)
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["revenue"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    import pandas as real_pd
    p = real_pd.read_json("data/events_large.ndjson", lines=True)
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
