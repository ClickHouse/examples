#!/usr/bin/env python3
"""Summarise one contention run dir: pgbench TPS / latency (avg + p95 from sampled per-txn logs),
analytics loop throughput, docker stats CPU% and memory per container."""
import sys, os, re, glob, statistics, json, gzip
d = sys.argv[1]
res = {"run": os.path.basename(d)}
log = open(os.path.join(d, "pgbench.log")).read()
m = re.search(r"tps = ([\d.]+) \(without initial connection time\)", log); res["tps"] = float(m.group(1)) if m else None
m = re.search(r"latency average = ([\d.]+) ms", log); res["lat_avg_ms"] = float(m.group(1)) if m else None
m = re.search(r"number of failed transactions: (\d+)", log); res["failed_txn"] = int(m.group(1)) if m else None
res["pgbench_aborted"] = "Run was aborted" in log
cl = os.path.join(d, "server_crash_log.txt")
if os.path.exists(cl): res["backend_sigkills"] = sum(1 for l in open(cl) if "signal 9" in l)
lats = []
for f in glob.glob(os.path.join(d, "pgbench_log", "pgbench_log.*")):
    for line in (gzip.open(f, "rt") if f.endswith(".gz") else open(f)):
        p = line.split()
        if len(p) >= 3 and p[2].isdigit(): lats.append(int(p[2]) / 1000.0)
lats.sort()
if lats:
    res["lat_p50_ms"] = round(lats[len(lats)//2], 2); res["lat_p95_ms"] = round(lats[int(len(lats)*0.95)], 2)
    res["lat_p99_ms"] = round(lats[int(len(lats)*0.99)], 2); res["lat_samples"] = len(lats)
loop = os.path.join(d, "analytics_loop.out")
if os.path.exists(loop):
    cur = None; t = {"Q3": [], "Q4": []}; errs = 0
    for line in open(loop):
        if line.startswith("ITER "): cur = line.split()[2]
        elif line.startswith("Time: ") and cur: t[cur].append(float(line.split()[1])); cur = None
        elif "ERROR" in line: errs += 1
    res["loop_q3_n"] = len(t["Q3"]); res["loop_q4_n"] = len(t["Q4"]); res["loop_errors"] = errs
    for q in t:
        if t[q]: res[f"loop_{q.lower()}_median_ms"] = round(statistics.median(t[q]), 1)
cpu = {}; mem = {}
def tobytes(s):
    s = s.strip(); m = re.match(r"([\d.]+)\s*([KMG]i?B|B)", s)
    if not m: return 0
    mult = {"B":1,"KiB":1024,"MiB":1024**2,"GiB":1024**3,"KB":1e3,"MB":1e6,"GB":1e9}[m.group(2)]
    return float(m.group(1)) * mult
for line in open(os.path.join(d, "docker_stats.csv")):
    p = line.strip().split(",")
    if len(p) < 4: continue
    name = p[1]; c = float(p[2].rstrip("%") or 0); used = tobytes(p[3].split("/")[0])
    cpu.setdefault(name, []).append(c); mem.setdefault(name, []).append(used)
for n in cpu:
    res[f"cpu_avg_pct[{n}]"] = round(statistics.mean(cpu[n]), 1)
    res[f"cpu_max_pct[{n}]"] = round(max(cpu[n]), 1)
    res[f"mem_max_GiB[{n}]"] = round(max(mem[n]) / 1024**3, 2)
print(json.dumps(res, indent=1))
