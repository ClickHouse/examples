#!/usr/bin/env python3
"""Read an Avro file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-avro-file-python

Run ./generate.sh first to create data/.
"""
import time

from chdb.datastore import DataStore


print("=== 1. Read an Avro file into a DataFrame (types auto-inferred) ===")
df = DataStore.from_file("data/events.avro", format="Avro")
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = df[df["event_type"] == "purchase"].groupby("country")["amount"].sum()
print(revenue)

print("\n=== 3. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 4. Performance: DataStore vs fastavro + manual loop, on a 3M-row Avro file ===")


def datastore_agg():
    d = DataStore.from_file("data/events_large.avro", format="Avro")
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["amount"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def fastavro_agg():
    import fastavro
    from collections import defaultdict
    agg = defaultdict(lambda: [0, 0.0])
    with open("data/events_large.avro", "rb") as f:
        for r in fastavro.reader(f):
            if r["event_type"] == "purchase":
                a = agg[r["country"]]
                a[0] += 1
                a[1] += r["amount"]
    return agg


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


fa_s = best_of_3(fastavro_agg)
ds_s = best_of_3(datastore_agg)
print(f"fastavro (manual loop):         {fa_s:.3f}s")
print(f"import chdb.datastore as pd:    {ds_s:.3f}s")
print(f"speedup:                        {fa_s / ds_s:.1f}x")
