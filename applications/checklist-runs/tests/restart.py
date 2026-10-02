"""Replace this fixture's exact PostgREST process and compare durable HTTP state.

Requires POSTGREST_PID, runtime/test env and the browser-snapshot.json recorded
by the browser helper in EVIDENCE_DIR. Never targets an arbitrary process.
"""

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import time

import psycopg

from acceptance import call, owner
from tls import APP, BINARY, environment

spec = importlib.util.spec_from_file_location(
    "fixture_tokens", APP / "scripts/tokens.py"
)
tokens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tokens)
evidence = Path(os.environ.get("EVIDENCE_DIR", "/tmp/checklist-evidence"))
evidence.mkdir(parents=True, exist_ok=True)
fixture = json.loads((evidence / "browser-snapshot.json").read_text())
old = int(os.environ["POSTGREST_PID"])
process = Path(f"/proc/{old}")
assert process.exists(), "The original PostgREST process is not live."
assert (process / "cwd").resolve() == APP
arguments = (process / "cmdline").read_bytes().split(b"\0")
assert Path(arguments[0].decode()).name == "postgrest"
assert b"postgrest.conf" in arguments
token = tokens.issue(os.environ["PGRST_JWT_SECRET"], "checklist_north")
detail_path = (
    "runs?id=eq."
    + fixture["run_id"]
    + "&select=*,run_steps(*),completions(*)&run_steps.order=step_number.asc&completions.order=step_number.asc"
)
status, before, _ = call(detail_path, token)
assert status == 200 and len(before) == 1 and before[0]["completed_steps"] == 3
with owner() as connection:
    completion = connection.execute(
        "SELECT request_id::text, step_number, note FROM checklist_storage.completions WHERE run_id = %s ORDER BY step_number LIMIT 1",
        (fixture["run_id"],),
    ).fetchone()
completion_request = {
    "p_request_id": completion[0],
    "p_run_id": fixture["run_id"],
    "p_step_number": completion[1],
    "p_note": completion[2],
}
start_before = call("rpc/start_run", token, fixture["request"])
completion_before = call("rpc/complete_step", token, completion_request)
assert start_before[0] == 200 and completion_before[0] == 200

os.kill(old, signal.SIGTERM)
deadline = time.monotonic() + 20
while process.exists() and time.monotonic() < deadline:
    time.sleep(0.1)
assert not process.exists(), "The original process did not exit; refusing replacement."
print(f"Original PostgREST PID {old} exited before replacement.", flush=True)
output = (evidence / "replacement-private.log").open("ab")
child = subprocess.Popen(
    [BINARY, "postgrest.conf"],
    cwd=APP,
    env=environment(),
    stdout=output,
    stderr=output,
    start_new_session=True,
)
(evidence / "replacement.pid").write_text(str(child.pid))
deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    assert child.poll() is None, "The replacement process exited before becoming ready."
    try:
        status, after, _ = call(detail_path, token)
        if status == 200:
            break
    except OSError:
        pass
    time.sleep(0.1)
else:
    raise AssertionError("Replacement did not become ready.")
assert before == after
assert call("rpc/start_run", token, fixture["request"])[:2] == start_before[:2]
assert call("rpc/complete_step", token, completion_request)[:2] == completion_before[:2]
child_keys = {
    item.split(b"=", 1)[0].decode()
    for item in Path(f"/proc/{child.pid}/environ").read_bytes().split(b"\0")
    if item
}
assert not any("OWNER" in key or "TEST_" in key or "ADMIN" in key for key in child_keys)
assert os.environ["PGUSER"] == "checklist_authenticator"
(evidence / "persistence.json").write_text(
    json.dumps(
        {
            "old_pid": old,
            "new_pid": child.pid,
            "before": before,
            "after": after,
            "start_result": start_before[1],
            "completion_result": completion_before[1],
        },
        indent=2,
    )
)
print(
    f"Replacement PID {child.pid} uses runtime-only env; exact run, three completions and both retained results agree."
)
