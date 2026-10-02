#!/usr/bin/env python3
"""Negative TLS through the actual production application, then genuine JVM restart."""
import argparse, json, os, signal, socket, subprocess, time, urllib.error, urllib.request
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
EVIDENCE = Path(os.environ["EVIDENCE_DIR"])
RUNTIME = ("PATH", "HOME", "LANG", "JDBC_URL", "PGUSER", "PGPASSWORD", "PGSSLROOTCERT", "ACCOUNT_001_TOKEN", "ACCOUNT_002_TOKEN")
base_env = {k:os.environ[k] for k in RUNTIME if k in os.environ}

def get(port, path, expected):
    req = urllib.request.Request(f"http://127.0.0.1:{port}"+path, headers={"Authorization":"Bearer "+os.environ["ACCOUNT_001_TOKEN"]})
    try:
        with urllib.request.urlopen(req,timeout=20) as r:
            status, body = r.status, r.read().decode()
    except urllib.error.HTTPError as r:
        status, body = r.code, r.read().decode()
    assert status == expected, (status,body)
    return json.loads(body) if body.startswith(("{","[")) else body

def ready(port, child=None):
    for _ in range(60):
        if child is not None and child.poll() is not None: return False
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/live", timeout=1) as r:
                if r.status==200: return True
        except Exception: time.sleep(.5)
    return False

def negative(name, overrides, markers, port):
    log = EVIDENCE/(name+".log")
    env=dict(base_env, QUARKUS_HTTP_PORT=str(port), **overrides)
    with log.open("w") as stream:
        child=subprocess.Popen(["python3",str(APP/"checks/launch.py")],env=env,stdout=stream,stderr=subprocess.STDOUT)
        try:
            if ready(port,child): get(port,"/documents",503)
            else:
                assert child.poll() is not None, "TLS control timed out without a conclusive startup failure"
        finally:
            if child.poll() is None: child.terminate()
            child.wait(timeout=20)
    text=log.read_text()
    marker=next((m for m in markers if m in text),None)
    assert marker is not None, "Expected specific TLS diagnostic absent; inspect private log"
    print(name, "specific driver cause:",marker)

parser=argparse.ArgumentParser()
parser.add_argument("--restart-only", action="store_true", help="Repeat only the process/persistence check")
args=parser.parse_args()
if not args.restart_only:
    get(8080,"/documents",200)
    negative("wrong-ca", {"PGSSLROOTCERT":"/etc/ssl/certs/ca-certificates.crt"},
             ["PKIX path building failed", "unable to find valid certification path to requested target"],8081)
    ip = next(row[4][0] for row in socket.getaddrinfo(os.environ["PGHOST"], int(os.environ["PGPORT"]),socket.AF_INET,socket.SOCK_STREAM))
    url = f"jdbc:postgresql://{ip}:{os.environ['PGPORT']}/{os.environ['PGDATABASE']}"
    negative("wrong-hostname", {"JDBC_URL":url},
             ["could not be verified by hostnameverifier", "could not be verified by hostname verifier"],8082)
    get(8080,"/documents",200)
    print("Same official-CA DNS endpoint positive control remains healthy")

saved=json.loads((EVIDENCE/"restart-document.json").read_text())
before_draft=get(8080,f"/documents/{saved['id']}/draft",200)
before_published=get(8080,f"/documents/{saved['id']}/published",200)
old=int((EVIDENCE/"server.pid").read_text())
os.kill(old,signal.SIGTERM)
for _ in range(100):
    try: os.kill(old,0)
    except ProcessLookupError: break
    time.sleep(.1)
else: raise AssertionError("Original JVM still exists; do not start replacement")
with (EVIDENCE/"restart-server.log").open("w") as stream:
    child=subprocess.Popen(["python3",str(APP/"checks/launch.py")],env=base_env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
(EVIDENCE/"server.pid").write_text(str(child.pid))
assert ready(8080,child), "Replacement JVM did not become ready"
assert child.pid != old
draft=get(8080,f"/documents/{saved['id']}/draft",200)
published=get(8080,f"/documents/{saved['id']}/published",200)
assert draft["revision"]==saved["draft"] and published["revision"]==saved["published"]
assert draft==before_draft and published==before_published, "Full immutable content changed across restart"
print("Production JVM restart:",old,"→",child.pid,"original exited; persisted draft",draft["revision"],"published",published["revision"])
print("Complete draft/published DTOs equal across restart (IDs, revision, title, body, timestamps)")
print("Genuine restart controls passed")
