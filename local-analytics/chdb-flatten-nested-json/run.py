#!/usr/bin/env python3
"""Flatten nested JSON in Python with chDB, a drop-in replacement for pandas.

Companion to:
https://clickhouse.com/resources/engineering/flatten-nested-json-python

Run ./generate.sh first to create data/.
"""
import time

import chdb.datastore as pd
import pandas as real_pd


print("=== 1. Read a nested JSON file into a DataFrame ===")
df = pd.read_json("data/orders.json")
print(df)
print(df.dtypes)

print("\n=== 2. Inspect the nested columns ===")
pdf0 = df.to_pandas()
print("customer[0]:", pdf0["customer"].iloc[0])
print("items[0]:   ", pdf0["items"].iloc[0])

print("\n=== 3. Explode items: one row per line item ===")
flat = df.explode("items")
print(flat.to_pandas()[["order_id", "items"]].to_string())

print("\n=== 4. Extract nested fields + compute line_total ===")
flat_pdf = flat.to_pandas().dropna(subset=["items"])
flat_pdf["country"] = flat_pdf["customer"].apply(lambda c: c["country"])
flat_pdf["tier"] = flat_pdf["customer"].apply(lambda c: c["tier"])
flat_pdf["sku"] = flat_pdf["items"].apply(lambda i: i["sku"])
flat_pdf["qty"] = flat_pdf["items"].apply(lambda i: i["qty"])
flat_pdf["price"] = flat_pdf["items"].apply(lambda i: i["price"])
flat_pdf["line_total"] = (flat_pdf["qty"] * flat_pdf["price"]).round(2)
result = flat_pdf[["order_id", "country", "tier", "sku", "qty", "line_total"]]
print(result.sort_values(["order_id", "sku"]).to_string(index=False))

print("\n=== 5. Aggregate: revenue per country ===")
revenue = flat_pdf.groupby("country")["line_total"].sum().round(2).sort_values(ascending=False)
print(revenue)

print("\n=== 6. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 7. Performance: chDB read_json+explode+extract vs pandas json_normalize ===")


def chdb_flatten():
    d = pd.read_json("data/orders_large.json")
    flat = d.explode("items")
    flat_pdf = flat.to_pandas().dropna(subset=["items"])
    flat_pdf["country"] = flat_pdf["customer"].apply(lambda c: c["country"])
    flat_pdf["revenue"] = flat_pdf["items"].apply(lambda i: i["qty"] * i["price"])
    return flat_pdf.groupby("country")["revenue"].sum().round(2).sort_index()


def pandas_flatten():
    import json
    with open("data/orders_large.json") as f:
        records = json.load(f)
    flat_pdf = real_pd.json_normalize(records, record_path="items", meta=[["customer", "country"]])
    flat_pdf["revenue"] = flat_pdf["qty"] * flat_pdf["price"]
    return flat_pdf.groupby("customer.country")["revenue"].sum().round(2).sort_index()


def best_of_3(fn):
    fn()  # warm
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


ds_s = best_of_3(chdb_flatten)
pd_s = best_of_3(pandas_flatten)
print(f"import pandas as pd (json_normalize):      {pd_s:.3f}s")
print(f"import chdb.datastore as pd (explode):     {ds_s:.3f}s")
print(f"speedup:                                   {pd_s / ds_s:.1f}x")
