#!/usr/bin/env python3
"""Read an Arrow (Arrow IPC / Feather) file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-arrow-file-python

Run ./generate.sh first to create data/events.arrow.
"""
import time

import chdb.datastore as pd


print("=== 1. Read an Arrow file into a DataFrame (types auto-inferred) ===")
df = pd.read_feather("data/events.arrow")
print(df.head(8))
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
counts = (df[df["event_type"] == "purchase"]
          .groupby("country")["id"].count()
          .sort_values(ascending=False))
print(counts)

print("\n=== 3. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 4. Performance: same code, one import swapped, on a 3M-row Arrow file ===")


def datastore_agg():
    d = pd.read_feather("data/events.arrow")
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["amount"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pyarrow_agg():
    import pyarrow.feather as feather
    tbl = feather.read_table("data/events.arrow")
    p = tbl.to_pandas()
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


pa_s = best_of_3(pyarrow_agg)
ds_s = best_of_3(datastore_agg)
print(f"pyarrow + pandas:               {pa_s:.3f}s")
print(f"import chdb.datastore as pd:    {ds_s:.3f}s")
print(f"speedup:                        {pa_s / ds_s:.1f}x")
