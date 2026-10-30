#!/usr/bin/env python3
"""Print markdown tables from results/queries/timings.csv (median and p10-p90 per path/query/mode) and
results/<contention dir>/*/summary.txt. Usage: make_tables.py [latency|contention|contention_select_only]"""
import csv, os, json, statistics, collections, sys
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
rows = list(csv.DictReader(open(os.path.join(base, "queries", "timings.csv"))))
latest = {}  # if a path/query/mode was run more than once, use the latest batch
for r in rows:
    k = (r["path"], r["query"], r["mode"]); latest[k] = max(latest.get(k, 0), int(r["ts"]))
data = collections.defaultdict(list)
for r in rows:
    k = (r["path"], r["query"], r["mode"])
    if int(r["ts"]) == latest[k]: data[k].append(float(r["ms"]))
order = [p for p in ["plain", "duckdb", "duckdb_tuned", "duckdb_parquet", "lake", "ch"] if any(k[0] == p for k in data)]
qs = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
def fmt(v): return "—" if v is None else (f"{v/1000:.2f} s" if v >= 1000 else f"{v:.0f} ms")
def q(v, f):  # inclusive quantile
    v = sorted(v); return v[0] + (v[-1] - v[0]) * 0 if len(v) == 1 else statistics.quantiles(v, n=100, method="inclusive")[f - 1]
for mode in ["warm", "cold"]:
    print(f"\n#### {mode.capitalize()}: median (n)\n\n| Query | " + " | ".join(order) + " |\n|---|" + "---:|" * len(order))
    for qq in qs:
        cells = []
        for p in order:
            v = data.get((p, qq, mode), [])
            cells.append("—" if not v else f"{fmt(statistics.median(v))}" + ("" if len(v) == 10 else f" (n={len(v)})"))
        print(f"| {qq} | " + " | ".join(cells) + " |")
    print(f"\n#### {mode.capitalize()}: p10–p90 spread\n\n| Query | " + " | ".join(order) + " |\n|---|" + "---:|" * len(order))
    for qq in qs:
        cells = []
        for p in order:
            v = data.get((p, qq, mode), [])
            cells.append("—" if len(v) < 2 else f"{fmt(q(v, 10))}–{fmt(q(v, 90))}")
        print(f"| {qq} | " + " | ".join(cells) + " |")
if len(sys.argv) > 1 and sys.argv[1] == "latency": sys.exit()
print("\n#### Contention\n")
print("| Run | TPS | Δ TPS | avg lat | p95 lat | p99 lat | analytics loop (Q3 / Q4 iterations, median ms) | PG CPU avg (max) | pgduck_server CPU avg | CH CPU avg (max) | PG mem max |")
print("|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|")
import sys
cdir = os.path.join(base, sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != "latency" else "contention"); base_tps = {}
runs = sorted(os.listdir(cdir), key=lambda r: (r.split("_")[0], 0 if "_none" in r else 1, r))
for r in runs:  # baseline = mean TPS of all "none" runs of that instance
    f = os.path.join(cdir, r, "summary.txt")
    if "_none" in r and os.path.exists(f): base_tps.setdefault(r.split("_")[0], []).append(json.load(open(f))["tps"])
base_tps = {k: statistics.mean(v) for k, v in base_tps.items()}
for r in runs:
    f = os.path.join(cdir, r, "summary.txt")
    if not os.path.exists(f): continue
    s = json.load(open(f)); inst = r.split("_")[0]
    pg = {"pgch": "lab-pgch", "pgduck": "lab-pgduck", "pglake": "lab-pglake"}[inst]
    d = f"{(s['tps']/base_tps[inst]-1)*100:+.0f}%" if inst in base_tps and "_none" not in r else "baseline"
    loop = f"{s.get('loop_q3_n','')} / {s.get('loop_q4_n','')}, {s.get('loop_q3_median_ms','')} / {s.get('loop_q4_median_ms','')}" if "loop_q3_n" in s else "—"
    pgd = f"{s.get('cpu_avg_pct[lab-pgduck-server]','—')}%" if inst == "pglake" else "—"
    print(f"| {r} | {s['tps']:.0f} | {d} | {s['lat_avg_ms']:.1f} ms | {s.get('lat_p95_ms','—')} ms | {s.get('lat_p99_ms','—')} ms | {loop} | "
          f"{s.get(f'cpu_avg_pct[{pg}]')}% ({s.get(f'cpu_max_pct[{pg}]')}%) | {pgd} | {s.get('cpu_avg_pct[lab-ch]')}% ({s.get('cpu_max_pct[lab-ch]')}%) | {s.get(f'mem_max_GiB[{pg}]')} GiB |")
