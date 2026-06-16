#!/usr/bin/env python3
"""Read a MessagePack (.msgpack) file in Python with chDB (drop-in pandas).

Companion to:
https://clickhouse.com/resources/engineering/read-messagepack-file-python

Run ./generate.sh first to create data/.
"""
import time
from collections import defaultdict

import chdb.datastore as pd
import msgpack

# MsgPack carries NO schema. You MUST pass the column list and types
# via structure=, in the same order the file was written.
SCHEMA = "event_id UInt64, country String, event_type String, amount Float64"


print("=== 1. Read MsgPack into a DataFrame (structure is REQUIRED) ===")
df = pd.DataStore.from_file("data/events.msgpack", format="MsgPack", structure=SCHEMA)
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
purchases = df[df["event_type"] == "purchase"].groupby("country")["amount"].sum()
print(purchases)

print("\n=== 3. What happens if you forget the structure ===")
try:
    bad = pd.DataStore.from_file("data/events.msgpack", format="MsgPack")
    bad.to_pandas()
except Exception as e:
    # Show just the CANNOT_EXTRACT_TABLE_STRUCTURE line
    for line in str(e).splitlines():
        if "CANNOT_EXTRACT_TABLE_STRUCTURE" in line or "cannot be extracted" in line:
            print(line)
            break

print("\n=== 4. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 5. Performance: chDB DataStore vs the msgpack library, on a 3M-row file ===")


def datastore_agg():
    d = pd.DataStore.from_file(
        "data/events_large.msgpack", format="MsgPack", structure=SCHEMA
    )
    r = (
        d[d["event_type"] == "purchase"]
        .groupby("country")["amount"]
        .sum()
        .sort_values(ascending=False)
    )
    return r.to_pandas()


def msgpack_lib_agg():
    # MsgPack is a flat stream of values with no row boundaries and no field
    # names, so you reshape it yourself: read 4 values per row and accumulate.
    agg = defaultdict(lambda: [0, 0.0])
    with open("data/events_large.msgpack", "rb") as f:
        vals = iter(msgpack.Unpacker(f, raw=False))
        while True:
            try:
                next(vals)                     # event_id
            except StopIteration:
                break
            country = next(vals)
            event_type = next(vals)
            amount = next(vals)
            if event_type == "purchase":
                a = agg[country]
                a[0] += 1
                a[1] += amount
    return agg


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


lib_s = best_of_3(msgpack_lib_agg)
ds_s = best_of_3(datastore_agg)
print(f"msgpack library (manual):           {lib_s:.3f}s")
print(f"chdb.datastore (pandas, no SQL):    {ds_s:.3f}s")
print(f"speedup:                            {lib_s / ds_s:.1f}x")
