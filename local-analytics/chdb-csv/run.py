#!/usr/bin/env python3
"""Read a CSV file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-csv-file-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd


print("=== 1. Read a CSV into a DataFrame (types auto-inferred) ===")
df = pd.read_csv("data/orders.csv")
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = df[df["product"] == "book"].groupby("country")["amount"].sum()
print(revenue)

print("\n=== 3. Headerless CSV: name the columns ===")
named = pd.read_csv(
    "data/orders_noheader.csv",
    names=["order_id", "country", "product", "amount", "order_date"],
)
print(named.head(3))

print("\n=== 4. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 5. Performance: same code, one import swapped, on a 3M-row CSV ===")


def datastore_agg():
    d = pd.read_csv("data/orders_large.csv")
    r = (d[d["product"] == "book"]
         .groupby("country")["amount"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    import pandas as real_pd
    p = real_pd.read_csv("data/orders_large.csv")
    return (p[p["product"] == "book"]
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
print(f"import pandas as pd:            {pd_s:.3f}s")
print(f"import chdb.datastore as pd:    {ds_s:.3f}s")
print(f"speedup:                        {pd_s / ds_s:.1f}x")
