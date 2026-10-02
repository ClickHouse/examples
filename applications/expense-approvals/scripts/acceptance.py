#!/usr/bin/env python3
"""Real HTTP acceptance against the dedicated Cloud fixture. No third party Python packages."""
import os, json, urllib.request, urllib.error, subprocess, time, concurrent.futures, uuid

BASE = "http://127.0.0.1:8081"
TOKENS = {e.split(":")[0]: e.split(":")[2] for e in os.environ["APP_TOKENS"].split(",")}
IDS = []


def req(method, path, actor="employee-a", body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if actor:
        headers["Authorization"] = "Bearer " + TOKENS[actor]
    try:
        with urllib.request.urlopen(
            urllib.request.Request(BASE + path, data, headers, method=method),
            timeout=60,
        ) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def expect(code, result):
    assert result[0] == code, (code, result)
    return result[1]


def create(actor="employee-a"):
    e = expect(
        201,
        req(
            "POST",
            "/expenses",
            actor,
            {"description": "Notebook", "amount": "12.34", "currency": "GBP"},
        ),
    )
    IDS.append(e["id"])
    return e


def start():
    f = open(os.environ.get("APP_LOG", "/tmp/expenses-app.log"), "a")
    runtime_env = {
        k: v
        for k, v in os.environ.items()
        if k
        in {
            "PATH",
            "HOME",
            "JAVA_HOME",
            "LANG",
            "APP_TOKENS",
            "PGHOST",
            "PGPORT",
            "PGDATABASE",
            "PGUSER",
            "PGPASSWORD",
            "PGSSLROOTCERT",
        }
    }
    runtime_env["PORT"] = "8081"
    p = subprocess.Popen(
        ["java", "-Xmx256m", "-jar", "target/expense-approvals-1.0.0.jar"],
        env=runtime_env,
        stdout=f,
        stderr=f,
    )
    for _ in range(90):
        if p.poll() is not None:
            raise RuntimeError("Application exited; inspect private application log")
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
    expect(401, req("GET", "/expenses", None))
    for amount in ["-1", "0", "1.001", "100000.01"]:
        expect(
            400,
            req(
                "POST",
                "/expenses",
                body={"description": "Bad", "amount": amount, "currency": "GBP"},
            ),
        )
    expect(
        400,
        req(
            "POST",
            "/expenses",
            body={"description": "Bad", "amount": "1.00", "currency": "USD"},
        ),
    )
    expect(
        400,
        req(
            "POST",
            "/expenses",
            body={
                "description": "Bad",
                "amount": "1.00",
                "currency": "GBP",
                "ownerId": "employee-b",
            },
        ),
    )
    e = create()
    path = "/expenses/" + e["id"]
    expect(404, req("GET", path, "employee-b"))
    expect(404, req("GET", path, "manager-a"))
    e = expect(
        200,
        req(
            "PUT",
            path,
            body={
                "description": "Edited",
                "amount": "22.10",
                "currency": "GBP",
                "version": 0,
            },
        ),
    )
    assert e["version"] == 1 and e["amount"] == "22.10"
    expect(409, req("POST", path + "/submit", body={"version": 0}))
    e = expect(200, req("POST", path + "/submit", body={"version": 1}))
    assert e["version"] == 2
    assert all(
        x["ownerId"] == "employee-b"
        for x in expect(200, req("GET", "/expenses", "employee-b"))
    )
    assert any(
        x["id"] == e["id"]
        for x in expect(200, req("GET", "/expenses?status=SUBMITTED", "manager-a"))
    )
    expect(400, req("POST", path + "/reject", "manager-a", {"version": 2}))
    expect(403, req("POST", path + "/approve", body={"version": 2}))
    expect(
        403,
        req(
            "PUT",
            path,
            "manager-a",
            {
                "description": "Hijack",
                "amount": "1.00",
                "currency": "GBP",
                "version": 2,
            },
        ),
    )
    e = expect(200, req("POST", path + "/approve", "manager-a", {"version": 2}))
    assert e["version"] == 3 and e["status"] == "APPROVED"
    expect(
        409,
        req("POST", path + "/reject", "manager-b", {"version": 2, "note": "Too late"}),
    )
    print(
        "PASS validation, ownership, role checks, draft edit/submit/approve and stale decisions",
        flush=True,
    )
    self = create("manager-a")
    sp = "/expenses/" + self["id"]
    expect(200, req("POST", sp + "/submit", "manager-a", {"version": 0}))
    expect(403, req("POST", sp + "/approve", "manager-a", {"version": 1}))
    expect(
        403, req("POST", sp + "/reject", "manager-a", {"version": 1, "note": "Self"})
    )
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for _ in range(3):
            race = create()
            rp = "/expenses/" + race["id"]
            jobs = [
                pool.submit(
                    req,
                    "PUT",
                    rp,
                    "employee-a",
                    {
                        "description": "Race edit",
                        "amount": "33.33",
                        "currency": "GBP",
                        "version": 0,
                    },
                ),
                pool.submit(req, "POST", rp + "/submit", "employee-a", {"version": 0}),
            ]
            results = [j.result() for j in jobs]
            assert sorted(r[0] for r in results) == [200, 409], results
            final = expect(200, req("GET", rp))
            assert final["version"] == 1
            if final["status"] == "DRAFT":
                assert final["description"] == "Race edit"
                expect(200, req("POST", rp + "/submit", body={"version": 1}))
                v = 2
            else:
                assert final["description"] == "Notebook"
                v = 1
            jobs = [
                pool.submit(req, "POST", rp + "/approve", "manager-a", {"version": v}),
                pool.submit(
                    req,
                    "POST",
                    rp + "/reject",
                    "manager-b",
                    {"version": v, "note": "Receipt missing"},
                ),
            ]
            results = [j.result() for j in jobs]
            assert sorted(r[0] for r in results) == [200, 409], results
            final = expect(200, req("GET", rp))
            assert final["version"] == v + 1 and final["decidedBy"] == (
                "manager-a" if results[0][0] == 200 else "manager-b"
            )
    print(
        "PASS three submit/edit races and three manager-decision races: exactly one commit and one HTTP 409 each",
        flush=True,
    )
    persist = create()
    pp = "/expenses/" + persist["id"]
    persist = expect(200, req("POST", pp + "/submit", body={"version": 0}))
    persist = expect(200, req("GET", pp))
    stop(p)
    p = start()
    assert expect(200, req("GET", pp)) == persist
    print(
        "PASS production process restart preserves exact expense and version",
        flush=True,
    )
finally:
    if p is not None and p.poll() is None:
        stop(p)
    if IDS:
        # Generated UUIDs only; runtime credential can delete fixture rows, API has no delete route.
        safe = ",".join("'" + str(uuid.UUID(id)) + "'" for id in IDS)
        subprocess.run(
            [
                "psql",
                "-X",
                "-v",
                "ON_ERROR_STOP=1",
                "-c",
                "DELETE FROM expenses.expense WHERE id IN (" + safe + ")",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
