#!/usr/bin/env python3
"""Run once on the documented fresh Cloud fixture; no local database substitute."""
import concurrent.futures
import json
import os
import subprocess
import time
import threading
import urllib.error
import urllib.request

ROOT = os.environ.get("API_URL", "http://127.0.0.1:3300")
TOKENS = json.loads(os.environ["ACCOUNT_TOKENS"])
A, B = sorted(TOKENS)


def http(account, path, body=None, raw=None):
    payload = raw if raw is not None else None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(ROOT + path, data=payload, headers={
        "Authorization": "Bearer " + TOKENS[account], "Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(request, timeout=60)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, json.loads(data) if data else None


def sql(statement, role="usage_migrator", password=None):
    env = dict(os.environ, PGUSER=role, PGSSLMODE="verify-full",
               PGPASSWORD=password or os.environ["USAGE_MIGRATOR_PASSWORD"])
    return subprocess.run(["psql", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-c", statement],
                          env=env, capture_output=True, text=True, timeout=30)


def rows(statement):
    result = sql(statement)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def parallel(body_factory, count=12):
    statuses = []
    lock = threading.Lock()
    def attempt(index):
        body = body_factory(index)
        deadline = time.monotonic() + 30
        while True:
            result = http(A, "/usage", body)
            with lock:
                statuses.append(result[0])
            if result[0] != 503 or time.monotonic() >= deadline:
                return result
            # A bounded pool can reject a transient connection failure. Preserve ID.
            time.sleep(0.25)
    with concurrent.futures.ThreadPoolExecutor(max_workers=count) as executor:
        results = list(executor.map(attempt, range(count)))
    print(f"HTTP burst: {count} clients; {len(statuses)} attempts; statuses " + str({status: statuses.count(status) for status in sorted(set(statuses))}), flush=True)
    return results


def main():
    assert http(A, "/quota")[1]["used"] == 8, "Requires fresh snapshot fixtures"
    assert http(B, "/quota")[1]["used"] == 4
    replay = {"requestId": "race-one-id", "feature": "api", "units": 2}
    same = parallel(lambda _: replay)
    assert sorted(status for status, _ in same) == [200] * 11 + [201]
    assert len({event["eventId"] for _, event in same}) == 1
    assert http(A, "/quota")[1]["used"] == 10
    assert http(A, "/usage", dict(replay, units=3))[0] == 409
    print("PASS: 12 matching requests, one event/debit; mismatched retry409")

    capped = parallel(lambda index: {"requestId": f"race-quota-{index}", "feature": "export", "units": 10})
    assert sorted(status for status, _ in capped) == [201] * 9 + [429] * 3
    assert http(A, "/quota")[1]["remaining"] == 0
    assert rows(f"SELECT sum(units) FROM usage.events WHERE account_id='{A}' AND usage_day=current_date") == "100"
    assert http(A, "/usage", replay)[0] == 200  # Retry still wins over exhausted quota.
    assert http(A, "/usage", dict(replay, feature="storage"))[0] == 409
    print("PASS: contended quota reached exactly100; three denied; exhausted replay preserved")

    assert http(B, "/events/race-one-id")[0] == 404
    assert http(A, "/usage", {"requestId": "invalid", "feature": "api", "units": 1, "accountId": B})[0] == 400
    assert http(A, "/usage", raw=b" " * 5000)[0] == 413
    assert http(A, "/reports?accountId=" + B)[0] == 400
    assert http(A, "/reports?from=2000-01-01")[0] == 400
    saved = TOKENS[A]
    TOKENS[A] = "not-a-token"
    assert http(A, "/quota")[0] == 401
    TOKENS[A] = saved
    print("PASS: account isolation, body/date bounds and authentication")

    before = http(B, "/quota")[1]
    setup = """
        SET ROLE usage_owner;
        CREATE FUNCTION usage.test_reject_event() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            IF NEW.request_id = 'force-rollback' THEN RAISE EXCEPTION 'test rollback'; END IF;
            RETURN NEW;
        END $$;
        CREATE TRIGGER test_reject_event BEFORE INSERT ON usage.events
        FOR EACH ROW EXECUTE FUNCTION usage.test_reject_event();
    """
    assert sql(setup).returncode == 0
    try:
        assert http(B, "/usage", {"requestId": "force-rollback", "feature": "api", "units": 1})[0] == 503
        assert http(B, "/quota")[1] == before
        assert http(B, "/events/force-rollback")[0] == 404
    finally:
        result = sql("SET ROLE usage_owner; DROP TRIGGER test_reject_event ON usage.events; DROP FUNCTION usage.test_reject_event();")
        assert result.returncode == 0, result.stderr
    print("PASS: database failure after counter mutation rolled back counter and event")

    for statement in ["UPDATE usage.events SET units=1", "DELETE FROM usage.events", "CREATE TABLE usage.forbidden(id int)", "SELECT * FROM usage.schema_migrations"]:
        result = sql(statement, "usage_app", os.environ["PGPASSWORD"])
        assert result.returncode != 0 and "permission denied" in result.stderr.lower()
    result = sql("SELECT * FROM usage.accounts", "usage_cdc", os.environ["USAGE_CDC_PASSWORD"])
    assert result.returncode != 0 and "permission denied" in result.stderr.lower()
    assert sql("SELECT count(*) FROM usage.events", "usage_cdc", os.environ["USAGE_CDC_PASSWORD"]).returncode == 0
    print("PASS: runtime mutation/schema denials; CDC reader limited to events")
    modest()


def modest():
    before = http(B, "/quota")[1]["used"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(lambda index: http(B, "/usage", {
            "requestId": f"modest-{index}", "feature": "storage", "units": 1}), range(3)))
    assert [status for status, _ in results] == [201] * 3
    assert http(B, "/quota")[1]["used"] == before + 3
    print("PASS: three concurrent clients, three HTTP attempts, three201, zero503; exactly three debits")


if __name__ == "__main__":
    main()
