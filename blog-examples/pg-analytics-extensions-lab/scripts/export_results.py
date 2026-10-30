#!/usr/bin/env python3
"""Collapse raw run output into the small set of files kept in git:
results/contention.csv (one row per pgbench run, both tests) and results/correctness.txt.
results/queries/timings.csv and results/explain/*.txt are written directly by the bench scripts."""
import csv, json, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__)); base = os.path.join(here, "..", "results")
cols = ["test", "run", "tps", "lat_avg_ms", "lat_p95_ms", "lat_p99_ms", "failed_txn", "pgbench_aborted", "backend_sigkills",
        "loop_q3_n", "loop_q4_n", "loop_errors", "loop_q3_median_ms", "loop_q4_median_ms"]
rows = []
for test, d in [("tpcb_120s", "contention"), ("select_only_60s", "contention_select_only")]:
    for run in sorted(os.listdir(os.path.join(base, d))) if os.path.isdir(os.path.join(base, d)) else []:
        f = os.path.join(base, d, run, "summary.txt")
        if not os.path.exists(f): continue
        s = json.load(open(f)); row = {"test": test, **{k: s.get(k, "") for k in cols[1:]}}
        for k, v in s.items():  # per-container CPU / memory columns
            if k.startswith(("cpu_avg_pct[", "cpu_max_pct[", "mem_max_GiB[")): row[k] = v
        rows.append(row)
extra = sorted({k for r in rows for k in r} - set(cols))
with open(os.path.join(base, "contention.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols + extra); w.writeheader(); w.writerows(rows)
out = subprocess.run([sys.executable, os.path.join(here, "compare_results.py")], capture_output=True, text=True).stdout
open(os.path.join(base, "correctness.txt"), "w").write(out)
print(f"wrote results/contention.csv ({len(rows)} runs) and results/correctness.txt")
