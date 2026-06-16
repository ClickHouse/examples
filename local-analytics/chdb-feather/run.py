#!/usr/bin/env python3
"""Read a Feather file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-feather-file-python

Run ./generate.sh first to create events.feather.
"""
import time

import pandas as real_pd
import chdb.datastore as pd

real_pd.set_option("display.float_format", "{:.2f}".format)


print("=== 1. Read a Feather file into a DataFrame (types auto-inferred) ===")
df = pd.read_feather("events.feather")
print(df.head(8))
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = (df[df["event_type"] == "purchase"]
           .groupby("country")["amount"].sum()
           .sort_values(ascending=False))
print(revenue.to_pandas())

print("\n=== 3. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 4. Performance: same code, one import swapped, on a 3M-row Feather file ===")


def datastore_agg():
    d = pd.read_feather("events.feather")
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["amount"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    p = real_pd.read_feather("events.feather")
    return (p[p["event_type"] == "purchase"]
            .groupby("country")["amount"].sum()
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
print(f"import pandas as pd:              {pd_s:.3f}s")
print(f"import chdb.datastore as pd:      {ds_s:.3f}s")
print(f"speedup:                          {pd_s / ds_s:.1f}x")
