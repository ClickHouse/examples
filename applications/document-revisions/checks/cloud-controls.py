#!/usr/bin/env python3
"""Real HTTP/Postgres checks. Requires runtime variables plus TEST_MIGRATOR_PASSWORD."""
import concurrent.futures, json, os, subprocess, urllib.error, urllib.request
from pathlib import Path
from datetime import datetime, timezone

BASE = "http://127.0.0.1:" + os.environ.get("QUARKUS_HTTP_PORT", "8080")
TOKEN = os.environ["ACCOUNT_001_TOKEN"]
OTHER = os.environ["ACCOUNT_002_TOKEN"]

def request(method, path, body=None, token=TOKEN, raw=None):
    payload = raw.encode() if raw is not None else (json.dumps(body).encode() if body is not None else None)
    headers = {"Content-Type": "application/json"}
    if token: headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read().decode(); return r.status, json.loads(text) if text.startswith(("{", "[")) else text
    except urllib.error.HTTPError as r:
        text = r.read().decode(); return r.code, json.loads(text) if text.startswith(("{", "[")) else text

def sql(statement, owner=False, expect_error=None):
    env = dict(os.environ)
    env["PGUSER"] = "revision_migrator" if owner else "revision_app"
    env["PGPASSWORD"] = os.environ["TEST_MIGRATOR_PASSWORD"] if owner else os.environ["PGPASSWORD"]
    prefix = "SET ROLE revision_owner; " if owner else ""
    run = subprocess.run(["psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-c", prefix + statement],
                         env=env, text=True, capture_output=True, timeout=20)
    if expect_error:
        assert run.returncode and expect_error in run.stderr, (run.returncode, run.stderr)
        print("SQL control:", expect_error)
    else:
        assert run.returncode == 0, run.stderr
        return run.stdout.strip().removeprefix("SET\n")

def expect(status, result):
    assert result[0] == status, result
    return result[1]

def create(title="Initial", body="First content"):
    return expect(201, request("POST", "/documents", {"title": title, "body": body}))

def edit(doc, expected, title, body="New content"):
    return request("POST", f"/documents/{doc}/revisions", {"expectedDraftRevision": expected, "title": title, "body": body})

def publish(doc, expected, number):
    return request("POST", f"/documents/{doc}/publication", {"expectedPublicationVersion": expected, "revision": number})

def race(functions):
    import threading
    barrier = threading.Barrier(len(functions))
    def run(f): barrier.wait(); return f()
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(functions)) as pool:
        return list(pool.map(run, functions))

expect(401, request("GET", "/documents", token=None))
expect(401, request("GET", "/documents", token="f" * 64))
for raw in ['{"title":"x","body":"x","accountId":"forged"}', '{"title":"x","body":"x"}{}',
            '{"title":9,"body":"x"}', '{"title":"x","title":"y","body":"x"}',
            '{"title":"x","body":"\\u0000"}', '{"title":"x","body":"\\ud800"}', 'null']:
    expect(400, request("POST", "/documents", raw=raw))
d = create(); doc = d["id"]
created = sql(f"SELECT (extract(epoch FROM created_at)*1000000)::bigint FROM revision_api.documents WHERE id='{doc}'")
instant = datetime.fromisoformat(d["createdAt"])
delta = instant - datetime(1970,1,1,tzinfo=timezone.utc)
assert (delta.days*86400 + delta.seconds)*1000000 + delta.microseconds == int(created)
for field in (None, "1", 1.5):
    expect(400, edit(doc, field, "Invalid"))
expect(404, request("GET", f"/documents/{doc}/draft", token=OTHER))
expect(404, request("POST", f"/documents/{doc}/revisions", {"expectedDraftRevision":1,"title":"Foreign","body":"No"}, token=OTHER))
expect(404, request("POST", f"/documents/{doc}/publication", {"expectedPublicationVersion":0,"revision":1}, token=OTHER))
expect(404, request("GET", f"/documents/{doc}/published"))
expect(200, publish(doc, 0, 1))
expect(200, edit(doc, 1, "Draft two", "Unpublished"))
assert expect(200, request("GET", f"/documents/{doc}/draft"))["body"] == "Unpublished"
assert expect(200, request("GET", f"/documents/{doc}/published"))["body"] == "First content"
expect(409, edit(doc, 1, "Stale"))
replay = expect(200, publish(doc, 0, 1)); assert replay["publicationVersion"] == 1
expect(404, publish(doc, 1, 999))
print("Authentication, strict parser/null/text controls, timestamp precision, ownership, draft/published separation and replay: passed")

results = race([lambda: edit(doc, 2, "Editor one"), lambda: edit(doc, 2, "Editor two")])
assert sorted(r[0] for r in results) == [200,409], results
assert sql(f"SELECT count(*) FROM revision_api.revisions WHERE document_id='{doc}'") == "3"
print("Concurrent HTTP editors:", sorted(r[0] for r in results), "three immutable revisions")
results = race([lambda: publish(doc, 1, 2), lambda: publish(doc, 1, 3)])
assert sorted(r[0] for r in results) == [200,409], results
selected = next(r[1] for r in results if r[0] == 200)
assert selected["publicationVersion"] == 2
again = expect(200, publish(doc, 1, selected["publishedRevision"])); assert again["publicationVersion"] == 2
expect(409, publish(doc, 0, selected["publishedRevision"]))
print("Concurrent different-target publications:", sorted(r[0] for r in results), "identical retry preserved version 2")

# Another document reaches revision four; the target document has only three.
b = create("Other document")["id"]
for number in (1,2,3): expect(200, edit(b, number, "Other revision"))
sql(f"BEGIN; UPDATE revision_api.documents SET published_revision=4, publication_version=3 WHERE id='{doc}'; COMMIT;", expect_error="23503")
assert sql(f"SELECT publication_version FROM revision_api.documents WHERE id='{doc}'") == "2"
sql(f"UPDATE revision_api.revisions SET body='tamper' WHERE document_id='{doc}';", expect_error="42501")
sql(f"DELETE FROM revision_api.revisions WHERE document_id='{doc}';", expect_error="42501")
sql("CREATE TABLE revision_api.forbidden(id integer);", expect_error="42501")
print("Cross-document deferred FK and immutable runtime permissions: passed")

# Force failure AFTER the revision INSERT is flushed, on the subsequent document UPDATE.
sql("""CREATE FUNCTION revision_api.reject_pointer() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.title='rollback-fail' THEN RAISE EXCEPTION 'synthetic pointer failure'; END IF; RETURN NEW; END $$;
CREATE TRIGGER reject_pointer BEFORE UPDATE ON revision_api.documents FOR EACH ROW EXECUTE FUNCTION revision_api.reject_pointer();""", owner=True)
try:
    expect(503, edit(doc, 3, "rollback-fail"))
    assert sql(f"SELECT draft_revision FROM revision_api.documents WHERE id='{doc}'") == "3"
    assert sql(f"SELECT count(*) FROM revision_api.revisions WHERE document_id='{doc}'") == "3"
finally:
    sql("DROP TRIGGER reject_pointer ON revision_api.documents; DROP FUNCTION revision_api.reject_pointer();", owner=True)
print("Failure after flushed revision INSERT rolled back content and draft pointer: passed")

# Method flushes both rows successfully; only deferred FK checking at COMMIT fails.
sql("""CREATE FUNCTION revision_api.break_commit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.title='deferred-fail' THEN NEW.number=999; END IF; RETURN NEW; END $$;
CREATE TRIGGER break_commit BEFORE INSERT ON revision_api.revisions FOR EACH ROW EXECUTE FUNCTION revision_api.break_commit();""", owner=True)
try:
    expect(503, request("POST", "/documents", {"title":"deferred-fail", "body":"Commit must fail"}))
    assert sql("SELECT count(*) FROM revision_api.documents WHERE title='deferred-fail'") == "0"
    assert sql("SELECT count(*) FROM revision_api.revisions WHERE title='deferred-fail'") == "0"
finally:
    sql("DROP TRIGGER break_commit ON revision_api.revisions; DROP FUNCTION revision_api.break_commit();", owner=True)
print("Deferred FK COMMIT failure returned 503, never 201; both rows absent: passed")
expect(200, edit(doc, 3, "Recovered after rollback"))
assert len(expect(200, request("GET", f"/documents/{doc}/revisions"))) == 4
assert expect(200, request("GET", f"/documents/{doc}/revisions/1"))["title"] == "Initial"
assert all(x["id"] != doc for x in expect(200, request("GET", "/documents", token=OTHER)))
Path(os.environ.get("EVIDENCE_DIR", "."), "restart-document.json").write_text(json.dumps({"id":doc,"draft":4,"published":selected["publishedRevision"]}))
print("Post-failure next transaction and bounded history/list scope: passed")
print("Live Cloud workflow controls passed")
