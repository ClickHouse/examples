"""Restart only this app's verified process, then compare its exact stored graph."""

import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request
from acceptance import call, owner

app = Path(__file__).resolve().parents[1]
evidence = Path(os.environ.get("EVIDENCE_DIR", "/tmp/task-dependencies-evidence"))
evidence.mkdir(parents=True, exist_ok=True)
project = "20000000-0000-4000-8000-000000000088"
with owner() as connection:
    connection.execute(
        "INSERT INTO task_dependencies.projects(id,account_id,name) VALUES (%s,%s,%s)",
        (project, "10000000-0000-4000-8000-000000000001", "Persistence fixture"),
    )
tasks = []
for title in ["Review draft", "Publish", "Notify team"]:
    status, result = call(
        f"/projects/{project}/tasks", method="POST", payload={"title": title}
    )
    assert status == 201
    tasks.append(result)
for dependent, prerequisite in zip(tasks[1:], tasks):
    status, _ = call(
        f"/projects/{project}/tasks/{dependent['id']}/prerequisites",
        method="POST",
        payload={"prerequisite_id": prerequisite["id"]},
    )
    assert status == 200
for task in tasks:
    status, result = call(
        f"/projects/{project}/tasks/{task['id']}/complete", method="POST", payload={}
    )
    assert status == 200 and result["done"] and result["done_at"]
status, before = call(f"/projects/{project}")
assert status == 200 and len(before["tasks"]) == 3 and len(before["edges"]) == 2
old = int(os.environ["API_PID"])
proc = Path(f"/proc/{old}")
assert (proc / "cwd").resolve() == app
assert (proc / "exe").resolve() == app / "bin/task-api"
os.kill(old, signal.SIGTERM)
deadline = time.monotonic() + 20
while proc.exists() and time.monotonic() < deadline:
    time.sleep(0.1)
assert not proc.exists(), "Old process did not exit; refusing replacement."
print(f"Original PID {old} exited before replacement.", flush=True)
keys = [
    "PGHOST",
    "PGPORT",
    "PGDATABASE",
    "PGUSER",
    "PGPASSWORD",
    "PGSSLMODE",
    "PGSSLROOTCERT",
    "PGCONNECT_TIMEOUT",
    "TASKS_NORTH_TOKEN",
    "TASKS_SOUTH_TOKEN",
]
environment = {
    "HOME": os.environ["HOME"],
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
    **{key: os.environ[key] for key in keys},
}
assert environment["PGUSER"] == "tasks_runtime"
child = subprocess.Popen(
    [str(app / "bin/task-api")],
    cwd=app,
    env=environment,
    stdout=(evidence / "replacement-private.log").open("ab"),
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
(evidence / "replacement.pid").write_text(str(child.pid))
deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    assert child.poll() is None
    try:
        status, after = call(f"/projects/{project}")
        if status == 200:
            break
    except OSError:
        pass
    time.sleep(0.2)
else:
    raise AssertionError("Replacement not ready.")
assert before == after
status, completed = call(
    f"/projects/{project}/tasks/{tasks[-1]['id']}/complete", method="POST", payload={}
)
assert status == 200 and completed == next(
    task for task in before["tasks"] if task["id"] == tasks[-1]["id"]
)
child_keys = {
    item.split(b"=", 1)[0].decode()
    for item in Path(f"/proc/{child.pid}/environ").read_bytes().split(b"\0")
    if item
}
assert not any("OWNER" in key or "TEST_" in key or "ADMIN" in key for key in child_keys)
(evidence / "persistence.json").write_text(
    json.dumps(
        {
            "old_pid": old,
            "new_pid": child.pid,
            "before": before,
            "after": after,
            "idempotent_completion": completed,
        },
        indent=2,
    )
)
print(
    f"Replacement PID {child.pid}: exact project/revision, three done tasks/timestamps and two edges agree; repeat completion unchanged; runtime-only credentials."
)
