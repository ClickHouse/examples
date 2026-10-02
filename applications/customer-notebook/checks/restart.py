import os
import pathlib
import signal
import time
from cloud import Session, CUSTOMERS, snapshot
from launch import launch

folder = pathlib.Path(os.environ["EVIDENCE_DIR"])
old = int((folder / "server.pid").read_text())
before = snapshot(CUSTOMERS[0])
os.kill(old, signal.SIGTERM)
for _ in range(100):
    try:
        os.kill(old, 0)
    except ProcessLookupError:
        break
    time.sleep(0.1)
else:
    raise AssertionError("Original runtime PID did not exit before restart")
with (folder / "server-restarted.log").open("w") as log:
    process = launch(log)
    assert process.pid != old
    (folder / "server.pid").write_text(str(process.pid))
    session = Session()  # In-memory CSRF sessions intentionally reset on restart.
    form = session.form(CUSTOMERS[0])
    assert int(form["revision"]) == before["revision"]
    assert snapshot(CUSTOMERS[0]) == before
    assert session.request(f"/customers/{CUSTOMERS[0]}/activity?from=2026-09-28&to=2026-09-30")[0] == 200
    print("Actual native process restart", old, "→", process.pid,
          "; original PID gone, retained profile/history unchanged, fresh session and report200;")
    print("Both children runtime-only; TZ Pacific/Auckland.")
