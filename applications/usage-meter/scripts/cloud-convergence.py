#!/usr/bin/env python3
"""Bounded equality check: PostgreSQL accepted events versus account-scoped reports."""
import datetime
import json
import os
import runpy
import time
from pathlib import Path

core = runpy.run_path(str(Path(__file__).with_name("cloud-core.py")))
today = datetime.datetime.now(datetime.timezone.utc).date()
start = today - datetime.timedelta(days=30)
expected = {}
for account in core["TOKENS"]:
    query = f"""
        SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) FROM (
            SELECT usage_day::text AS "usageDay", feature, sum(units)::bigint AS units, count(*) AS events
            FROM usage.events WHERE account_id='{account}'::uuid
                AND usage_day BETWEEN '{start}'::date AND '{today}'::date
            GROUP BY usage_day, feature ORDER BY usage_day, feature
        ) t
    """
    expected[account] = json.loads(core["rows"](query))

deadline = time.monotonic() + 180
began = time.monotonic()
while True:
    reports = {}
    matched = True
    for account, rows in expected.items():
        status, report = core["http"](account, f"/reports?from={start}&to={today}")
        if status != 200:
            matched = False
            continue
        assert report["accountId"] == account and report["consistency"] == "eventual"
        assert report["quotaAuthority"] == "postgres" and len(report["features"]) <= 93
        reports[account] = report
        matched = matched and report["features"] == rows
        daily = {}
        for row in rows:
            daily.setdefault(row["usageDay"], {"usageDay": row["usageDay"], "units": 0, "events": 0})
            daily[row["usageDay"]]["units"] += row["units"]
            daily[row["usageDay"]]["events"] += row["events"]
        matched = matched and report["daily"] == list(daily.values())
    if matched:
        print(f"PASS: exact day/feature sum and count equality for both accounts; observed wait{time.monotonic()-began:.1f}s")
        output = os.environ.get("REPORT_EVIDENCE")
        if output:
            Path(output).write_text(json.dumps({"expected": expected, "reports": reports}, indent=2))
        break
    if time.monotonic() >= deadline:
        raise RuntimeError("Report convergence deadline180s exceeded")
    print(f"Waiting for CDC convergence; elapsed{time.monotonic()-began:.1f}s", flush=True)
    time.sleep(5)
