#!/usr/bin/env python3
"""Run prepare; pause pipe; paused; revoke report SELECT; outage; restore SELECT; recover."""
import concurrent.futures
import json
import runpy
import sys
from pathlib import Path

core = runpy.run_path(str(Path(__file__).with_name("cloud-core.py")))
http, account = core["http"], core["B"]
state_path = Path(".deployment/lag-before.json")
mode = sys.argv[1]
if mode == "prepare":
    status, report = http(account, "/reports")
    assert status == 200
    quota = http(account, "/quota")[1]
    state_path.write_text(json.dumps({"report": report, "quota": quota}))
    print("Saved converged report and authoritative counter before pause")
elif mode == "paused":
    before = json.loads(state_path.read_text())
    status, event = http(account, "/usage", {"requestId": "while-paused", "feature": "export", "units": 6})
    assert status == 201
    quota = http(account, "/quota")[1]
    assert quota["used"] == before["quota"]["used"] + 6
    status, report = http(account, "/reports")
    assert status == 200 and report == before["report"]
    print(f"PASS: paused CDC; PostgreSQL used{quota['used']}, report still reflects used{before['quota']['used']}; event persisted")
elif mode == "outage":
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda target: http(target, "/reports"), core["TOKENS"]))
    assert [status for status, _ in results] == [503, 503]
    before = http(account, "/quota")[1]
    status, _ = http(account, "/usage", {"requestId": "while-analytics-denied", "feature": "api", "units": 1})
    assert status == 201 and http(account, "/quota")[1]["used"] == before["used"] + 1
    print("PASS: both report capacity slots failed503; operational quota and accepted write succeeded")
elif mode == "recover":
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda target: http(target, "/reports"), core["TOKENS"]))
    assert [status for status, _ in results] == [200, 200]
    print("PASS: both report capacity slots recovered200 in the same API process/client")
else:
    raise ValueError("Expected prepare, paused, outage or recover")
