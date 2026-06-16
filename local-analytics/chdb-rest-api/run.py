#!/usr/bin/env python3
"""Query a REST API in Python with chDB, reading responses into a DataFrame.

Companion to:
https://clickhouse.com/resources/engineering/query-rest-api-with-sql-python

Run ./generate.sh first to create data/. This script serves data/ over a local
http.server so DataStore.from_url() has a real HTTP endpoint to hit -- the same
call works against any JSON API.
"""
import http.server
import json
import threading
import time
import urllib.request

from chdb.datastore import DataStore

PORT = 8731
BASE = f"http://127.0.0.1:{PORT}"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory="data", **k)

    def log_message(self, *a, **k):
        pass  # suppress per-request access log lines

    def handle_one_request(self):
        # chDB can close the connection early once it has read enough data;
        # swallow the resulting broken-pipe noise so the demo output stays clean.
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True


def serve_data_dir():
    """Serve ./data over HTTP in a background thread (stands in for a real API)."""
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), QuietHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


httpd = serve_data_dir()
time.sleep(0.3)  # let the server bind

print("=== 1. Read a JSON API response into a DataFrame ===")
df = DataStore.from_url(f"{BASE}/orders.json", format="JSONEachRow")
print(df)
print(df.dtypes)

print("\n=== 2. Filter + aggregate the way you already do (pandas, not SQL) ===")
revenue = (
    df[df["status"] != "closed"]
    .groupby("country")["amount"]
    .sum()
    .sort_values(ascending=False)
)
print(revenue.to_pandas())

print("\n=== 3. Hand off to real pandas when you need it ===")
pdf = df.to_pandas()
print(type(pdf))

print("\n=== 4. Multiple pages: read each URL, then concat ===")
import pandas as real_pd

page1 = DataStore.from_url(f"{BASE}/orders_page1.json", format="JSONEachRow").to_pandas()
page2 = DataStore.from_url(f"{BASE}/orders_page2.json", format="JSONEachRow").to_pandas()
pages = real_pd.concat([page1, page2], ignore_index=True)
result = pages.groupby("country")["amount"].sum().sort_values(ascending=False)
print(result)

print("\n=== 5. Performance: DataStore.from_url vs urllib + json + manual aggregation ===")


def datastore_agg():
    d = DataStore.from_url(f"{BASE}/orders_large.json", format="JSONEachRow")
    r = (
        d[d["status"] == "open"]
        .groupby("country")["amount"]
        .sum()
        .sort_values(ascending=False)
    )
    return r.to_pandas()


def requests_agg():
    # urllib stands in for requests here; the parse loop is identical either way.
    agg = {}
    with urllib.request.urlopen(f"{BASE}/orders_large.json") as resp:
        for line in resp:
            r = json.loads(line)
            if r["status"] == "open":
                a = agg.setdefault(r["country"], [0, 0.0])
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


ds_s = best_of_3(datastore_agg)
py_s = best_of_3(requests_agg)
print("# Apple M4 Pro (14 cores, 24 GB RAM, macOS); chDB 4.1.8, Python 3.14; best-of-3, warm.")
print("# Served over localhost -- network latency removed, isolates parse+aggregate cost.")
print(f"requests + json + manual agg:   {py_s:.3f}s")
print(f"DataStore.from_url (chDB):      {ds_s:.3f}s")
print(f"speedup:                        {py_s / ds_s:.1f}x")

httpd.shutdown()
