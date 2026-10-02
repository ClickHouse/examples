#!/usr/bin/env python3
"""HTTP checks against the dedicated Cloud fixture; uses only Python's standard library."""
import os, json, urllib.request, urllib.error, subprocess, time, concurrent.futures, uuid

BASE = "http://127.0.0.1:8081"
TOKENS = {e.split(":")[0]: e.split(":")[1] for e in os.environ["APP_TOKENS"].split(",")}
IDS = []


def req(method, path, owner="user-a", body=None):
    headers = {"Content-Type": "application/json"}
    if owner:
        headers["Authorization"] = "Bearer " + TOKENS[owner]
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(
            urllib.request.Request(BASE + path, data, headers, method=method),
            timeout=60,
        ) as r:
            s = r.read()
            return r.status, json.loads(s) if s else None
    except urllib.error.HTTPError as e:
        s = e.read()
        try:
            body = json.loads(s) if s else None
        except ValueError:
            body = None
        return e.code, body


def expect(code, result):
    assert result[0] == code, (code, result)
    return result[1]


def create(owner="user-a"):
    h = expect(201, req("POST", "/habits", owner, {"name": "Read a chapter"}))
    IDS.append(h["id"])
    return "/habits/" + h["id"]


def start():
    env = {
        k: v
        for k, v in os.environ.items()
        if k
        in {
            "PATH",
            "HOME",
            "DOTNET_ROOT",
            "LANG",
            "PGHOST",
            "PGPORT",
            "PGDATABASE",
            "PGUSER",
            "PGPASSWORD",
            "PGSSLROOTCERT",
            "APP_TOKENS",
        }
    }
    env["APP_URL"] = BASE
    env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    f = open(os.environ.get("APP_LOG", "/tmp/habit-api.log"), "a")
    p = subprocess.Popen(
        ["dotnet", "HabitApi/bin/Release/net10.0/HabitApi.dll"],
        env=env,
        stdout=f,
        stderr=f,
    )
    for _ in range(90):
        if p.poll() is not None:
            raise RuntimeError("Application exited; inspect private log")
        try:
            if req("GET", "/health", None)[0] == 200:
                return p
        except OSError:
            pass
        time.sleep(1)
    p.terminate()
    raise RuntimeError("Application startup timeout")


def stop(p):
    p.terminate()
    p.wait(timeout=30)


p = None
try:
    p = start()
    expect(401, req("GET", "/habits", None))
    for name in ["", " ", "x" * 101, "Nul\0name"]:
        expect(400, req("POST", "/habits", body={"name": name}))
    expect(400, req("POST", "/habits", body={"name": "Forged", "ownerId": "user-b"}))
    expect(413, req("POST", "/habits", body={"name": "x" * 5000}))
    path = create()
    for date in [
        "2026-02-29",
        "2026-2-03",
        "1999-12-31",
        "2101-01-01",
        "2026-10-03T00:00:00Z",
    ]:
        expect(400, req("PUT", path + "/check-ins/" + date))
    for month in ["2026-13", "2026-2", "1999-12"]:
        expect(400, req("GET", path + "/history?month=" + month))
    for method, suffix in [
        ("PUT", "/check-ins/2026-10-03"),
        ("DELETE", "/check-ins/2026-10-03"),
        ("POST", "/archive"),
        ("GET", "/history?month=2026-10"),
    ]:
        expect(404, req(method, path + suffix, "user-b"))
    assert all(
        h["id"] != path.split("/")[-1]
        for h in expect(200, req("GET", "/habits", "user-b"))
    )
    first = expect(200, req("PUT", path + "/check-ins/2026-10-03"))
    again = expect(200, req("PUT", path + "/check-ins/2026-10-03"))
    assert first["id"] == again["id"] and again["completedOn"] == "2026-10-03"
    expect(200, req("PUT", path + "/check-ins/2026-09-30"))
    expect(200, req("PUT", path + "/check-ins/2026-11-01"))
    history = expect(200, req("GET", path + "/history?month=2026-10"))
    assert len(history) == 1 and history[0]["id"] == first["id"]
    print(
        "PASS explicit date/month validation, input bounds, forged-owner rejection and cross-user reads/writes",
        flush=True,
    )
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        cp = create()
        jobs = [pool.submit(req, "PUT", cp + "/check-ins/2026-10-05") for _ in range(8)]
        results = [expect(200, j.result()) for j in jobs]
        assert len({r["id"] for r in results}) == 1
        assert len(expect(200, req("GET", cp + "/history?month=2026-10"))) == 1
        for _ in range(4):
            ap = create()
            a = pool.submit(req, "PUT", ap + "/check-ins/2026-10-05")
            b = pool.submit(req, "POST", ap + "/archive")
            complete = a.result()
            expect(200, b.result())
            assert complete[0] in [200, 409], complete
            hist = expect(200, req("GET", ap + "/history?month=2026-10"))
            assert len(hist) == (1 if complete[0] == 200 else 0)
            expect(409, req("PUT", ap + "/check-ins/2026-10-06"))
    expect(200, req("POST", path + "/archive"))
    expect(200, req("POST", path + "/archive"))
    assert expect(200, req("GET", path + "/history?month=2026-10")) == history
    assert expect(200, req("PUT", path + "/check-ins/2026-10-03")) == history[0]
    expect(409, req("PUT", path + "/check-ins/2026-10-04"))
    expect(204, req("DELETE", path + "/check-ins/2026-10-03"))
    expect(204, req("DELETE", path + "/check-ins/2026-10-03"))
    assert expect(200, req("GET", path + "/history?month=2026-10")) == []
    expect(409, req("PUT", path + "/check-ins/2026-10-03"))
    print(
        "PASS eight duplicate check-ins share one durable id; four archive/check-in races; archived replay/undo and history retention",
        flush=True,
    )
    month = create()
    for day in [31, 1, 15]:
        expect(200, req("PUT", month + "/check-ins/2026-10-" + str(day).zfill(2)))
    before = expect(200, req("GET", month + "/history?month=2026-10"))
    assert [c["completedOn"] for c in before] == [
        "2026-10-01",
        "2026-10-15",
        "2026-10-31",
    ] and len(before) <= 31
    stop(p)
    p = start()
    assert expect(200, req("GET", month + "/history?month=2026-10")) == before
    print(
        "PASS ordered bounded monthly history and production-process restart persistence",
        flush=True,
    )
finally:
    if p is not None and p.poll() is None:
        stop(p)
    if IDS:
        safe = ",".join("'" + str(uuid.UUID(id)) + "'" for id in IDS)
        subprocess.run(
            [
                "psql",
                "-X",
                "-v",
                "ON_ERROR_STOP=1",
                "-c",
                "DELETE FROM habits.habit WHERE id IN (" + safe + ")",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
