#!/usr/bin/env python3
"""Read a .npy file in Python with chDB's DataStore API.

Companion to:
https://clickhouse.com/resources/engineering/read-npy-file-python

Run ./generate.sh first to create data/.
"""
import time

from chdb.datastore import DataStore


print("=== 1. Read a .npy file into a DataFrame ===")
# DataStore.from_file reads the array into a lazy, ClickHouse-backed object.
# A .npy holds one numeric array with no column names, so chDB exposes a
# single column called "array".
df = DataStore.from_file("data/readings.npy", format="Npy")
print(df)
print(df.dtypes)

print("\n=== 2. Filter and aggregate the way you already do ===")
# Filter and aggregate with the pandas API you already use — no SQL.
mean_val = df["array"].mean()
print(f"mean: {float(mean_val):.2f}")

max_val = df["array"].max()
min_val = df["array"].min()
print(f"max: {float(max_val):.2f}  min: {float(min_val):.2f}")

print("\n=== 3. A 2-D .npy reads as one row per outer element ===")
mat = DataStore.from_file("data/matrix.npy", format="Npy")
print(mat)

print("\n=== 4. Join two arrays by position (readings + quality flags) ===")
# Load each array separately, hand off to real pandas, then align by index.
readings_pdf = df.to_pandas()
flags_df = DataStore.from_file("data/flags.npy", format="Npy")
flags_pdf = flags_df.to_pandas()
flags_pdf = flags_pdf.rename(columns={"array": "ok"})
readings_pdf = readings_pdf.rename(columns={"array": "reading"})
combined = readings_pdf.join(flags_pdf)
print(combined)

print("\n=== 5. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))
# Filter in real pandas after materialising:
good = pdf[pdf["array"] > 75]
print(f"readings above 75: {len(good)}")

print("\n=== 6. Performance: DataStore vs numpy.load (mean of 3M-element array) ===")


def datastore_mean():
    d = DataStore.from_file("data/large.npy", format="Npy")
    return float(d["array"].mean())


def numpy_mean():
    import numpy as np
    v = np.load("data/large.npy")
    return v.mean()


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


np_s = best_of_3(numpy_mean)
ds_s = best_of_3(datastore_mean)
print(f"numpy.load + .mean():           {np_s:.3f}s")
print(f"DataStore.from_file + .mean():  {ds_s:.3f}s")
if ds_s < np_s:
    print(f"speedup:                        {np_s / ds_s:.1f}x")
else:
    print(f"numpy faster by:                {ds_s / np_s:.1f}x")
