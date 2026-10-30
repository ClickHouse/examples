#!/usr/bin/env python3
"""Compare the first-run result set of every query across paths (normalises numeric formatting / trailing zeros)."""
import os, re, sys, hashlib
base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results", "queries")
def rows(path):
    txt = open(path).read(); m = re.search(r"RUN 1\n(.*?)\nTime: ", txt, re.S)
    if not m: return None
    out = []
    lines = m.group(1).splitlines(); started = False
    for ln in lines:
        if not started:
            started = bool(ln.strip()) and set(ln.strip()) <= set("-+"); continue
        if re.match(r"\(\d+ rows?\)", ln.strip()) or not ln.strip(): continue
        cells = [c.strip() for c in ln.split("|")]
        norm = []
        for c in cells:
            c = re.sub(r"\+00$", "", c)               # timestamptz suffix
            try: c = repr(round(float(c), 2))
            except ValueError: pass
            norm.append(c)
        out.append(tuple(norm))
    return out
paths = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
print("query  " + "  ".join(f"{p:>14}" for p in paths))
for q in ["Q1","Q2","Q3","Q4","Q5","Q6"]:
    hs = []
    for p in paths:
        f = os.path.join(base, p, q + ".out")
        r = rows(f) if os.path.exists(f) else None
        hs.append("missing" if r is None else hashlib.md5(repr(r).encode()).hexdigest()[:8] + f"/{len(r)}r")
    print(f"{q:5}  " + "  ".join(f"{h:>14}" for h in hs) + ("   MATCH" if len(set(hs)) == 1 else "   DIFF"))
