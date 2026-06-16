#!/usr/bin/env python3
"""Read a TSV file in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/read-tsv-file-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd


print("=== 1. Read a TSV into a DataFrame (types auto-inferred) ===")
df = pd.read_csv("data/events.tsv", sep="\t")
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = (df[df["event_type"] == "purchase"]
           .groupby("country")["revenue"].sum())
print(revenue)

print("\n=== 3. Headerless TSV: name the columns ===")
named = pd.read_csv(
    "data/events_noheader.tsv",
    sep="\t",
    names=["event_id", "country", "event_type", "revenue", "product"],
)
print(named.head(3))

print("\n=== 4. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 5. Performance: same code, one import swapped, on a 3M-row TSV ===")


def datastore_agg():
    d = pd.read_csv("data/events_large.tsv", sep="\t")
    r = (d[d["event_type"] == "purchase"]
         .groupby("country")["revenue"].sum()
         .sort_values(ascending=False))
    return r.to_pandas()


def pandas_agg():
    import pandas as real_pd
    p = real_pd.read_csv("data/events_large.tsv", sep="\t")
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
