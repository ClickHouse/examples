#!/usr/bin/env python3
"""Read a BSON file in Python with chDB.

Companion to:
https://clickhouse.com/resources/engineering/read-bson-file-python

Run ./generate.sh first to create data/.
The perf contrast needs pymongo's bson decoder: pip install pymongo
"""
import time

from chdb.datastore import DataStore


print("=== 1. Read a BSON file into a DataFrame (schema auto-inferred) ===")
df = DataStore.from_file("data/events.bson", format="BSONEachRow")
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
purchases = df[df["event_type"] == "purchase"].groupby("country")["revenue"].sum()
print(purchases.to_pandas().round(2))

print("\n=== 3. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 4. Performance: chDB DataStore vs pymongo decode + pandas on a 2M-row BSON ===")


def datastore_agg():
    d = DataStore.from_file("data/events_large.bson", format="BSONEachRow")
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["revenue"]
         .sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pymongo_pandas_agg():
    import pandas as pd
    from bson import decode_file_iter
    with open("data/events_large.bson", "rb") as f:
        pdf = pd.DataFrame(decode_file_iter(f))
    p = pdf[pdf.event_type == b"purchase"]
    return (p.groupby("country")["revenue"]
             .sum()
             .sort_values(ascending=False))


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


py_s = best_of_3(pymongo_pandas_agg)
ds_s = best_of_3(datastore_agg)
print(f"pymongo decode + pandas:        {py_s:.3f}s")
print(f"import chdb.datastore:          {ds_s:.3f}s")
print(f"speedup:                        {py_s / ds_s:.1f}x")
