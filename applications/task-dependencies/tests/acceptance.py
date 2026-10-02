"""Actual disposable Cloud/HTTP acceptance. No database substitutes."""

import concurrent.futures
import contextlib
import json
import os
from pathlib import Path
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
import psycopg

BASE = os.environ.get("API_BASE_URL", "http://127.0.0.1:8090")
NORTH = "10000000-0000-4000-8000-000000000001"
SOUTH = "10000000-0000-4000-8000-000000000002"
TOKEN = os.environ["TASKS_NORTH_TOKEN"]
SOUTH_TOKEN = os.environ["TASKS_SOUTH_TOKEN"]


def owner():
    return psycopg.connect(
        user=os.environ["TEST_OWNER_USER"],
        password=os.environ["TEST_OWNER_PASSWORD"],
        autocommit=True,
    )


def call(path, token=TOKEN, method="GET", payload=None, raw=None, origin=None):
    body = (
        raw
        if raw is not None
        else (json.dumps(payload).encode() if payload is not None else None)
    )
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    if origin:
        headers["Origin"] = origin
    request = urllib.request.Request(
        BASE + "/api" + path, data=body, headers=headers, method=method
    )
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, json.loads(data) if data else None


def observe_waiters(connection, blocker, expected):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        count = connection.execute(
            """WITH RECURSIVE waiting(pid) AS (
          SELECT pid FROM pg_locks WHERE NOT granted AND %s = ANY(pg_blocking_pids(pid))
          UNION SELECT l.pid FROM pg_locks l JOIN waiting w ON w.pid=ANY(pg_blocking_pids(l.pid)) WHERE NOT l.granted
        ) SELECT count(DISTINCT pid) FROM waiting""",
            (blocker,),
        ).fetchone()[0]
        if count >= expected:
            print(
                f"Observed {count} independent HTTP transactions in the real project lock queue.",
                flush=True,
            )
            return
        time.sleep(0.05)
    raise AssertionError(
        "Expected HTTP transactions were not observed waiting on project lock."
    )


class CloudHTTP(unittest.TestCase):
    def setUp(self):
        self.project = str(uuid.uuid4())
        self.other = str(uuid.uuid4())
        with owner() as connection:
            connection.execute(
                "INSERT INTO task_dependencies.projects(id,account_id,name) VALUES (%s,%s,'Acceptance north'),(%s,%s,'Acceptance south')",
                (self.project, NORTH, self.other, SOUTH),
            )

    def tearDown(self):
        with owner() as connection:
            connection.execute(
                "DELETE FROM task_dependencies.edges WHERE project_id=ANY(%s::uuid[])",
                ([self.project, self.other],),
            )
            connection.execute(
                "DELETE FROM task_dependencies.tasks WHERE project_id=ANY(%s::uuid[])",
                ([self.project, self.other],),
            )
            connection.execute(
                "DELETE FROM task_dependencies.projects WHERE id=ANY(%s::uuid[])",
                ([self.project, self.other],),
            )

    def task(self, title="Acceptance task", project=None, token=TOKEN):
        status, result = call(
            f"/projects/{project or self.project}/tasks",
            token,
            "POST",
            {"title": title},
        )
        self.assertEqual(status, 201, result)
        return result

    def edge(self, task, prerequisite):
        return call(
            f"/projects/{self.project}/tasks/{task}/prerequisites",
            method="POST",
            payload={"prerequisite_id": prerequisite},
        )

    def complete(self, task):
        return call(
            f"/projects/{self.project}/tasks/{task}/complete", method="POST", payload={}
        )

    def snapshot(self):
        status, result = call(f"/projects/{self.project}")
        self.assertEqual(status, 200, result)
        return result

    def test_01_workflow_duplicate_and_repeat_safe(self):
        a = self.task("Review")["id"]
        b = self.task("Publish")["id"]
        first = self.edge(b, a)
        self.assertEqual(first[0], 200)
        before = self.snapshot()["project"]["revision"]
        self.assertEqual(self.edge(b, a), first)
        self.assertEqual(self.snapshot()["project"]["revision"], before)
        self.assertEqual(self.complete(b)[0], 409)
        self.assertTrue(self.complete(a)[1]["done"])
        result = self.complete(b)
        self.assertEqual(result[0], 200)
        self.assertTrue(result[1]["done"])
        self.assertIsNotNone(result[1]["done_at"])
        self.assertEqual(self.complete(b), result)
        self.assertEqual(self.edge(b, a), first)
        extra = self.task()["id"]
        self.assertEqual(self.edge(b, extra)[0], 409)
        path = f"/projects/{self.project}/tasks/{b}/prerequisites/{a}"
        self.assertEqual(call(path, method="DELETE")[0], 204)
        revision = self.snapshot()["project"]["revision"]
        self.assertEqual(call(path, method="DELETE")[0], 204)
        self.assertEqual(self.snapshot()["project"]["revision"], revision)

    def test_02_direct_and_long_cycles(self):
        tasks = [self.task(str(i))["id"] for i in range(6)]
        for a, b in zip(tasks, tasks[1:]):
            self.assertEqual(self.edge(a, b)[0], 200)
        self.assertEqual(self.edge(tasks[-1], tasks[0])[1]["error"], "CYCLE")
        self.assertEqual(self.edge(tasks[0], tasks[0])[1]["error"], "CYCLE")
        self.assertEqual(len(self.snapshot()["edges"]), 5)

    def test_03_opposite_edge_contention(self):
        a = self.task()["id"]
        b = self.task()["id"]
        barrier = threading.Barrier(3)
        with owner() as held, owner() as observer, concurrent.futures.ThreadPoolExecutor(
            2
        ) as pool:
            with held.transaction():
                blocker = held.execute("SELECT pg_backend_pid()").fetchone()[0]
                held.execute(
                    "SELECT id FROM task_dependencies.projects WHERE id=%s FOR UPDATE",
                    (self.project,),
                )

                def add(left, right):
                    barrier.wait()
                    return self.edge(left, right)

                pending = [pool.submit(add, a, b), pool.submit(add, b, a)]
                barrier.wait()
                observe_waiters(observer, blocker, 2)
            results = [future.result() for future in pending]
        self.assertEqual(sorted(result[0] for result in results), [200, 409])
        self.assertEqual(len(self.snapshot()["edges"]), 1)

    def test_04_completion_against_new_prerequisite(self):
        a = self.task()["id"]
        b = self.task()["id"]
        barrier = threading.Barrier(3)
        with owner() as held, owner() as observer, concurrent.futures.ThreadPoolExecutor(
            2
        ) as pool:
            with held.transaction():
                blocker = held.execute("SELECT pg_backend_pid()").fetchone()[0]
                held.execute(
                    "SELECT id FROM task_dependencies.projects WHERE id=%s FOR UPDATE",
                    (self.project,),
                )

                def add():
                    barrier.wait()
                    return self.edge(a, b)

                def complete():
                    barrier.wait()
                    return self.complete(a)

                pending = [pool.submit(add), pool.submit(complete)]
                barrier.wait()
                observe_waiters(observer, blocker, 2)
            added, completed = [future.result() for future in pending]
        snapshot = self.snapshot()
        task = next(task for task in snapshot["tasks"] if task["id"] == a)
        if added[0] == 200:
            self.assertEqual(completed[0], 409)
            self.assertFalse(task["done"])
            self.assertEqual(len(snapshot["edges"]), 1)
        else:
            self.assertEqual(added[0], 409)
            self.assertEqual(completed[0], 200)
            self.assertTrue(task["done"])
            self.assertEqual(snapshot["edges"], [])
        print(
            "Actual coordinated edge/complete outcome:",
            added[0],
            completed[0],
            flush=True,
        )

    def test_05_multiwrite_rollback(self):
        revision = self.snapshot()["project"]["revision"]
        with owner() as connection:
            connection.execute(
                """CREATE FUNCTION task_dependencies.acceptance_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.title='fail-after-revision' THEN RAISE EXCEPTION 'private owner fixture' USING ERRCODE='23514'; END IF; RETURN NEW; END $$"""
            )
            connection.execute(
                "CREATE TRIGGER acceptance_fail BEFORE INSERT ON task_dependencies.tasks FOR EACH ROW EXECUTE FUNCTION task_dependencies.acceptance_fail()"
            )
        try:
            status, result = call(
                f"/projects/{self.project}/tasks",
                method="POST",
                payload={"title": "fail-after-revision"},
            )
            self.assertEqual(status, 503)
            self.assertNotIn("private", json.dumps(result))
            after = self.snapshot()
            self.assertEqual(after["project"]["revision"], revision)
            self.assertEqual(after["tasks"], [])
        finally:
            with owner() as connection:
                connection.execute(
                    "DROP TRIGGER acceptance_fail ON task_dependencies.tasks"
                )
                connection.execute("DROP FUNCTION task_dependencies.acceptance_fail()")

    def test_06_account_scope_and_composite_keys(self):
        a = self.task()["id"]
        b = self.task(project=self.other, token=SOUTH_TOKEN)["id"]
        self.assertEqual(call(f"/projects/{self.other}")[0], 404)
        self.assertEqual(
            call(
                f"/projects/{self.other}/tasks",
                method="POST",
                payload={"title": "forged"},
            )[0],
            404,
        )
        self.assertEqual(self.edge(a, b)[0], 404)
        with owner() as connection:
            for task, prerequisite, code in [(a, b, "23503"), (a, a, "23514")]:
                with self.assertRaises(psycopg.Error) as error:
                    connection.execute(
                        "INSERT INTO task_dependencies.edges(project_id,task_id,prerequisite_id) VALUES (%s,%s,%s)",
                        (self.project, task, prerequisite),
                    )
                self.assertEqual(error.exception.sqlstate, code)
        status, projects = call("/projects")
        self.assertEqual(status, 200)
        self.assertLessEqual(len(projects), 20)
        self.assertEqual([p["id"] for p in projects], sorted(p["id"] for p in projects))
        self.assertNotIn(self.other, [p["id"] for p in projects])

    def test_07_graph_bounds(self):
        ids = [str(uuid.uuid4()) for _ in range(100)]
        with owner() as connection:
            with connection.transaction():
                for task in ids:
                    connection.execute(
                        "INSERT INTO task_dependencies.tasks(id,project_id,title) VALUES (%s,%s,%s)",
                        (task, self.project, "Bound fixture"),
                    )
                pairs = [(a, b) for i, a in enumerate(ids) for b in ids[i + 1 :]][:300]
                for a, b in pairs:
                    connection.execute(
                        "INSERT INTO task_dependencies.edges(project_id,task_id,prerequisite_id) VALUES (%s,%s,%s)",
                        (self.project, a, b),
                    )
            with self.assertRaises(psycopg.Error) as failure:
                connection.execute(
                    "INSERT INTO task_dependencies.tasks(id,project_id,title) VALUES (%s,%s,%s)",
                    (str(uuid.uuid4()), self.project, "One too many"),
                )
            self.assertEqual(failure.exception.sqlstate, "23514")
            with self.assertRaises(psycopg.Error) as failure:
                connection.execute(
                    "INSERT INTO task_dependencies.edges(project_id,task_id,prerequisite_id) VALUES (%s,%s,%s)",
                    (self.project, ids[10], ids[99]),
                )
            self.assertEqual(failure.exception.sqlstate, "23514")
        self.assertEqual(
            call(
                f"/projects/{self.project}/tasks",
                method="POST",
                payload={"title": "Over limit"},
            )[1]["error"],
            "TASK_LIMIT",
        )
        self.assertEqual(self.edge(ids[10], ids[99])[1]["error"], "EDGE_LIMIT")
        snapshot = self.snapshot()
        self.assertEqual(len(snapshot["tasks"]), 100)
        self.assertEqual(len(snapshot["edges"]), 300)

    def test_08_http_boundaries(self):
        path = f"/projects/{self.project}/tasks"
        for raw, status in [
            (b'{"title":"x","title":"y"}', 400),
            (b'{"title":null}', 422),
            (b'{"title":"\\ud800"}', 422),
            (b'{"title":"bad\\u0085"}', 422),
            (b'{"title":42}', 400),
            (b'{"title":"' + b"x" * 9000 + b'"}', 400),
        ]:
            self.assertEqual(call(path, method="POST", raw=raw)[0], status)
        self.assertEqual(
            call(path, method="POST", payload={"title": "Plan 🚀"})[0], 201
        )
        self.assertEqual(call("/projects/--000000-0000-4000-8000-000000000001")[0], 400)
        self.assertEqual(
            call(
                path,
                method="POST",
                payload={"title": "x"},
                origin="https://foreign.invalid",
            )[0],
            403,
        )
        self.assertEqual(call("/projects", token="forged")[0], 401)
        self.assertEqual(call("/projects?after=bad")[0], 400)
        with owner() as connection:
            connection.execute(
                "UPDATE task_dependencies.projects SET revision=1000000000 WHERE id=%s",
                (self.project,),
            )
        self.assertEqual(
            call(path, method="POST", payload={"title": "At revision cap"})[1]["error"],
            "REVISION_LIMIT",
        )

    def test_09_runtime_roles(self):
        with psycopg.connect() as connection:
            flags = connection.execute(
                "SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user"
            ).fetchone()
            self.assertEqual(flags, (False, False, False))
        for sql in [
            "CREATE TABLE task_dependencies.forbidden(id int)",
            "CREATE TEMP TABLE forbidden(id int)",
            "SET ROLE tasks_owner",
            "UPDATE task_dependencies.tasks SET title=title",
            "DELETE FROM task_dependencies.tasks",
            "UPDATE task_dependencies.projects SET account_id=account_id",
        ]:
            with psycopg.connect(autocommit=True) as connection:
                with self.assertRaises(psycopg.Error):
                    connection.execute(sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
