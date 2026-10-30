#!/usr/bin/env python3
"""Print markdown tables from results/queries/timings.csv and results/contention/*/summary.txt.
If a path/query was run more than once, the LAST batch (latest ts) is used."""
import csv, os, json, statistics, collections
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
rows = list(csv.DictReader(open(os.path.join(base, "queries", "timings.csv"))))
latest = {}
for r in rows:
    k = (r["path"], r["query"]); latest[k] = max(latest.get(k, 0), int(r["ts"]))
data = collections.defaultdict(dict)
for r in rows:
    k = (r["path"], r["query"])
    if int(r["ts"]) == latest[k]: data[k][int(r["run"])] = float(r["ms"])
order = [p for p in ["plain", "duckdb", "duckdb_tuned", "duckdb_parquet", "lake", "ch"] if any(k[0] == p for k in data)]
qs = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
def fmt(v): return "—" if v is None else (f"{v/1000:.2f} s" if v >= 1000 else f"{v:.0f} ms")
for title, pick in [("Warm (median of runs 2-4)", lambda d: statistics.median([d[i] for i in (2,3,4) if i in d]) if any(i in d for i in (2,3,4)) else None),
                    ("Cold (run 1)", lambda d: d.get(1))]:
    print(f"\n#### {title}\n\n| Query | " + " | ".join(order) + " |\n|---|" + "---:|" * len(order))
    for q in qs:
        print(f"| {q} | " + " | ".join(fmt(pick(data.get((p, q), {}))) for p in order) + " |")
print("\n#### Contention\n")
print("| Run | TPS | Δ TPS | avg lat | p95 lat | p99 lat | analytics loop (Q3 / Q4 iterations, median ms) | PG CPU avg (max) | pgduck_server CPU avg | CH CPU avg (max) | PG mem max |")
print("|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|")
import sys
cdir = os.path.join(base, sys.argv[1] if len(sys.argv) > 1 else "contention"); base_tps = {}
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
