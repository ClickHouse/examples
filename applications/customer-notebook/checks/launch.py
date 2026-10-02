"""Launch a native runtime child without setup/test credentials."""
import os
import pathlib
import subprocess
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
KEYS = ["PGHOST", "PGPORT", "PGDATABASE", "PGSSLROOTCERT",
        "NOTEBOOK_APP_PASSWORD", "NOTEBOOK_REPORT_PASSWORD"]


def launch(log):
    environment = {key: os.environ[key] for key in KEYS}
    environment.update(HOME=os.environ["HOME"], PATH=os.environ["PATH"], TZ="Pacific/Auckland")
    process = subprocess.Popen([str(pathlib.Path.home() / ".local/bin/clojure"),
                                "-Sdeps", (ROOT / "deps-lock.edn").read_text(), "-M:locked:run"],
                               cwd=ROOT, env=environment, stdout=log, stderr=log,
                               start_new_session=True)
    for _ in range(100):
        assert process.poll() is None, "Native server exited before readiness"
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=1) as response:
                if response.status == 200:
                    return process
        except OSError:
            time.sleep(0.1)
    process.terminate()
    process.wait(timeout=10)
    raise AssertionError("Native server readiness deadline")


if __name__ == "__main__":
    folder = pathlib.Path(os.environ["EVIDENCE_DIR"])
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "server-runtime.log").open("w") as log:
        process = launch(log)
        (folder / "server.pid").write_text(str(process.pid))
        print("Runtime-only native child ready; PID", process.pid, "TZ Pacific/Auckland")
