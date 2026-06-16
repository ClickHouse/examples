#!/usr/bin/env python3
"""Read a JSONL file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-jsonl-file-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd


print("=== 1. Read a JSONL file into a DataFrame (types auto-inferred) ===")
df = pd.read_json("data/orders.jsonl", lines=True)
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = (df[df["status"] == "paid"]
           .groupby("country")["amount"].sum()
           .sort_values(ascending=False))
print(revenue)

print("\n=== 3. Access nested fields and explode arrays with pandas ===")
# Materialize once, then work on the real pandas DataFrame
pdf_small = df.to_pandas()

# customer comes back as [id, tier]; index 1 is the tier
pdf_small["tier"] = pdf_small["customer"].apply(lambda c: c[1])
print(pdf_small[["order_id", "country", "status", "tier"]].to_string(index=False))

# skus is an array; explode flattens it into one row per sku
paid = pdf_small[pdf_small["status"] == "paid"][["country", "skus"]].explode("skus")
print(paid.dropna(subset=["skus"]).reset_index(drop=True))

print("\n=== 4. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 5. Performance: same code, one import swapped, on a 2M-row JSONL ===")


def datastore_agg():
    d = pd.read_json("data/orders_large.jsonl", lines=True)
    r = (d[d["status"] == "paid"]
         .groupby("country")["amount"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    import pandas as real_pd
    p = real_pd.read_json("data/orders_large.jsonl", lines=True)
    return (p[p["status"] == "paid"]
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
