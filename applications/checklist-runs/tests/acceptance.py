"""Real HTTP/RLS/transaction controls against an explicitly disposable Cloud fixture."""

from concurrent.futures import ThreadPoolExecutor
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid

import psycopg

spec = importlib.util.spec_from_file_location(
    "tokens", Path(__file__).parents[1] / "scripts/tokens.py"
)
tokens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tokens)
BASE = os.environ.get("API_BASE_URL", "http://127.0.0.1:3000")
TEMPLATE = "10000000-0000-4000-8000-000000000001"
SECRET = os.environ["PGRST_JWT_SECRET"]


def signed(claims, secret=SECRET):
    values = [{"alg": "HS256", "typ": "JWT"}, claims]
    body = ".".join(
        tokens.b64url(json.dumps(v, separators=(",", ":")).encode()) for v in values
    )
    return (
        body
        + "."
        + tokens.b64url(
            hmac.new(secret.encode(), body.encode(), hashlib.sha256).digest()
        )
    )


def call(path, token=None, payload=None, method=None, headers=None):
    request_headers = {"Authorization": "Bearer " + token} if token else {}
    request_headers.update(headers or {})
    data = None if payload is None else json.dumps(payload).encode()
    if data is not None:
        request_headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        BASE + "/" + path, data=data, headers=request_headers, method=method
    )
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    return response.status, json.loads(raw) if raw else None, dict(response.headers)


def owner():
    return psycopg.connect(
        user=os.environ["TEST_OWNER_USER"], password=os.environ["TEST_OWNER_PASSWORD"]
    )


def wait_for_blockers(connection, count=2):
    blocker = connection.info.backend_pid
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        observed = connection.execute(
            """WITH RECURSIVE blockers(request_pid, blocked_by) AS (
                SELECT DISTINCT pid, unnest(pg_blocking_pids(pid)) FROM pg_locks WHERE NOT granted
                UNION
                SELECT b.request_pid, unnest(pg_blocking_pids(b.blocked_by)) FROM blockers b
            ) SELECT count(DISTINCT request_pid) FROM blockers WHERE blocked_by = %s""",
            (blocker,),
        ).fetchone()[0]
        if observed >= count:
            print(
                f"Observed {observed} independent HTTP transactions blocked by owner PID {blocker}.",
                flush=True,
            )
            return
        time.sleep(0.05)
    raise AssertionError("Competing HTTP work did not reach the held database lock.")


class CloudAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.north = tokens.issue(SECRET, "checklist_north")
        cls.south = tokens.issue(SECRET, "checklist_south")

    def start(self, label, key=None, token=None):
        payload = {
            "p_request_id": key or str(uuid.uuid4()),
            "p_template_id": TEMPLATE,
            "p_label": label,
        }
        status, value, _ = call("rpc/start_run", token or self.north, payload)
        self.assertEqual(status, 200, value)
        self.assertIsInstance(value["run_id"], str)
        return value, payload

    def complete(self, run_id, step, key=None, note="", token=None):
        payload = {
            "p_request_id": key or str(uuid.uuid4()),
            "p_run_id": run_id,
            "p_step_number": step,
            "p_note": note,
        }
        return call("rpc/complete_step", token or self.north, payload), payload

    def test_01_lifecycle_snapshot_and_retained_results(self):
        initial, payload = self.start("  Acceptance opening  ")
        status, repeated, _ = call(
            "rpc/start_run", self.north, {**payload, "p_label": "Acceptance opening"}
        )
        self.assertEqual((status, repeated), (200, initial))
        self.assertEqual(
            call("rpc/start_run", self.north, {**payload, "p_label": "Changed"})[0], 409
        )
        path = (
            "runs?id=eq."
            + initial["run_id"]
            + "&select=*,run_steps(*),completions(*)&run_steps.order=step_number.asc"
        )
        status, rows, _ = call(path, self.north)
        self.assertEqual(status, 200, rows)
        self.assertEqual(
            [s["title"] for s in rows[0]["run_steps"]],
            ["Check lights", "Arrange chairs", "Test display"],
        )
        first = None
        for step in range(1, 4):
            (status, result, _), completion_payload = self.complete(
                initial["run_id"], step, note="  Checked  "
            )
            self.assertEqual(status, 200, result)
            self.assertEqual(result["completed_steps"], step)
            if step == 1:
                first = result, completion_payload
        self.assertEqual(result["status"], "completed")
        self.assertEqual(
            call("rpc/complete_step", self.north, first[1])[:2], (200, first[0])
        )
        self.assertEqual(
            call("rpc/complete_step", self.north, {**first[1], "p_note": "Changed"})[0],
            409,
        )
        self.assertEqual(self.complete(initial["run_id"], 1)[0][0], 409)
        self.assertEqual(call("rpc/start_run", self.north, payload)[:2], (200, initial))
        final = call(path, self.north)[1][0]
        self.assertEqual((final["completed_steps"], len(final["completions"])), (3, 3))

    def test_02_competing_matching_starts(self):
        payload = {
            "p_request_id": str(uuid.uuid4()),
            "p_template_id": TEMPLATE,
            "p_label": "Concurrent start",
        }
        with owner() as connection, ThreadPoolExecutor(max_workers=2) as workers:
            connection.execute(
                "SELECT 1 FROM checklist_storage.operators WHERE role_name = 'checklist_north' FOR UPDATE"
            )
            requests = [
                workers.submit(call, "rpc/start_run", self.north, payload)
                for _ in range(2)
            ]
            wait_for_blockers(connection)
            connection.commit()
            responses = [request.result() for request in requests]
        self.assertEqual([r[0] for r in responses], [200, 200], responses)
        self.assertEqual(responses[0][1], responses[1][1])
        with owner() as connection:
            count = connection.execute(
                "SELECT count(*) FROM checklist_storage.runs WHERE operator_role = 'checklist_north' AND request_id = %s",
                (payload["p_request_id"],),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_03_competing_completions_increment_once(self):
        run, _ = self.start("Concurrent completion")
        payload = {
            "p_request_id": str(uuid.uuid4()),
            "p_run_id": run["run_id"],
            "p_step_number": 1,
            "p_note": "One retained note",
        }
        with owner() as connection, ThreadPoolExecutor(max_workers=2) as workers:
            connection.execute(
                "SELECT 1 FROM checklist_storage.runs WHERE id = %s FOR UPDATE",
                (run["run_id"],),
            )
            requests = [
                workers.submit(call, "rpc/complete_step", self.north, payload)
                for _ in range(2)
            ]
            wait_for_blockers(connection)
            connection.commit()
            responses = [request.result() for request in requests]
        self.assertEqual([r[0] for r in responses], [200, 200], responses)
        self.assertEqual(responses[0][1], responses[1][1])
        with owner() as connection:
            row = connection.execute(
                "SELECT completed_steps, (SELECT count(*) FROM checklist_storage.completions WHERE run_id = r.id) FROM checklist_storage.runs r WHERE r.id = %s",
                (run["run_id"],),
            ).fetchone()
        self.assertEqual(row, (1, 1))
        self.assertEqual(self.complete(run["run_id"], 1)[0][0], 409)

    def test_04_after_update_child_failure_rolls_back(self):
        run, _ = self.start("Rollback control")
        with owner() as connection:
            connection.execute(
                """CREATE FUNCTION checklist_storage.fail_completion() RETURNS trigger
                LANGUAGE plpgsql SET search_path = pg_catalog AS $$ BEGIN
                IF NEW.note = 'after-update-failure' THEN RAISE check_violation USING MESSAGE = 'Synthetic child failure'; END IF;
                RETURN NEW; END; $$"""
            )
            connection.execute(
                "CREATE TRIGGER fail_completion BEFORE INSERT ON checklist_storage.completions FOR EACH ROW EXECUTE FUNCTION checklist_storage.fail_completion()"
            )
        try:
            (status, value, _), payload = self.complete(
                run["run_id"], 1, note="after-update-failure"
            )
            self.assertEqual(status, 400, value)
            self.assertEqual(value["code"], "23514")
            with owner() as connection:
                row = connection.execute(
                    "SELECT completed_steps, (SELECT count(*) FROM checklist_storage.completions WHERE run_id = r.id) FROM checklist_storage.runs r WHERE r.id = %s",
                    (run["run_id"],),
                ).fetchone()
            self.assertEqual(row, (0, 0))
        finally:
            with owner() as connection:
                connection.execute(
                    "DROP TRIGGER fail_completion ON checklist_storage.completions"
                )
                connection.execute("DROP FUNCTION checklist_storage.fail_completion()")
        self.assertEqual(call("rpc/complete_step", self.north, payload)[0], 200)

    def test_05_scope_and_exposed_write_denial(self):
        run, _ = self.start("North private")
        self.assertEqual(
            call(
                "runs?id=eq." + run["run_id"] + "&select=*,run_steps(*),completions(*)",
                self.south,
            )[:2],
            (200, []),
        )
        self.assertEqual(
            call("run_steps?run_id=eq." + run["run_id"], self.south)[:2], (200, [])
        )
        self.assertEqual(self.complete(run["run_id"], 1, token=self.south)[0][0], 404)
        self.assertEqual(call("runs", self.north, {"label": "Direct insert"})[0], 403)
        self.assertEqual(
            call("templates", self.north, {"title": "Edited"}, method="PATCH")[0], 403
        )
        self.assertEqual(
            call("runs", self.north, headers={"Accept-Profile": "checklist_storage"})[
                0
            ],
            406,
        )
        southern, _ = self.start("South private", token=self.south)
        self.assertNotIn(
            southern["run_id"], [r["id"] for r in call("rpc/list_runs", self.north)[1]]
        )

    def test_06_native_jwt_rejections(self):
        now = int(time.time())
        good = {
            "role": "checklist_north",
            "aud": "checklist-runs",
            "iat": now,
            "exp": now + 60,
        }
        self.assertEqual(call("templates")[0], 401)
        cases = [
            signed(good, "b" * 128),
            signed({**good, "iat": now - 180, "exp": now - 120}),
            signed({**good, "aud": "wrong-audience"}),
            signed({k: v for k, v in good.items() if k != "aud"}),
            signed({**good, "exp": now + 901}),
        ]
        for value in cases:
            self.assertEqual(call("templates", value)[0], 401)
        self.assertEqual(
            call("templates", signed({**good, "role": "checklist_owner"}))[0], 403
        )

    def test_07_numeric_cursor_exact_bigint_and_get_read_only(self):
        self.assertEqual(call("rpc/list_runs?p_limit=21", self.north)[0], 422)
        self.assertEqual(call("rpc/list_runs?p_after=-1", self.north)[0], 422)
        self.assertLessEqual(len(call("runs?limit=1000", self.north)[1]), 20)
        with owner() as connection:
            connection.execute(
                "ALTER SEQUENCE checklist_storage.runs_id_seq RESTART WITH 9007199254740993"
            )
        run, payload = self.start("Exact large ID")
        self.assertEqual(run["run_id"], "9007199254740993")
        self.assertEqual(
            call("rpc/list_runs?p_after=9007199254740992", self.north)[1][0]["id"],
            run["run_id"],
        )
        self.assertEqual(self.complete(run["run_id"], 1)[0][0], 200)
        params = urllib.parse.urlencode({**payload, "p_request_id": str(uuid.uuid4())})
        status, value, _ = call("rpc/start_run?" + params, self.north)
        self.assertEqual(status, 405, value)
        self.assertEqual(value["code"], "25006")
        self.assertEqual(
            call("rpc/start_run", self.north, {**payload, "p_label": "x" * 81})[0], 422
        )
        self.assertEqual(
            call("rpc/start_run", self.north, {**payload, "p_label": "bad\u0001label"})[
                0
            ],
            422,
        )

    def test_09_native_json_and_scalar_boundaries(self):
        payload = {
            "p_request_id": str(uuid.uuid4()),
            "p_template_id": TEMPLATE,
            "p_label": "Native input boundary",
        }
        self.assertEqual(
            call("rpc/start_run", self.north, {**payload, "p_label": "\ud800"})[0], 400
        )
        self.assertEqual(
            call(
                "rpc/start_run", self.north, {**payload, "p_template_id": "not-a-uuid"}
            )[0],
            400,
        )
        self.assertEqual(
            call("rpc/start_run", self.north, {**payload, "p_label": None})[0], 422
        )
        completion = {
            "p_request_id": str(uuid.uuid4()),
            "p_run_id": "1" * 5000,
            "p_step_number": 1,
            "p_note": "",
        }
        self.assertEqual(call("rpc/complete_step", self.north, completion)[0], 400)
        with owner() as connection:
            self.assertEqual(
                connection.execute(
                    "SELECT count(*) FROM checklist_storage.runs WHERE request_id = %s",
                    (payload["p_request_id"],),
                ).fetchone()[0],
                0,
            )

    def test_08_authenticator_memberships_roles_and_quota(self):
        with psycopg.connect() as connection:
            self.assertEqual(
                connection.execute(
                    "SELECT rolinherit FROM pg_roles WHERE rolname = current_user"
                ).fetchone()[0],
                False,
            )
            roles = connection.execute(
                "SELECT parent.rolname FROM pg_auth_members m JOIN pg_roles parent ON parent.oid = m.roleid JOIN pg_roles child ON child.oid = m.member WHERE child.rolname = current_user ORDER BY parent.rolname"
            ).fetchall()
            self.assertEqual(roles, [("checklist_north",), ("checklist_south",)])
            for sql in (
                "SET ROLE checklist_owner",
                "CREATE TABLE public.denied(id int)",
                "CREATE TEMP TABLE denied(id int)",
                "SELECT * FROM checklist_storage.runs",
            ):
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    connection.execute(sql)
                connection.rollback()
            connection.execute("SET ROLE checklist_north")
            self.assertEqual(
                connection.execute(
                    "SELECT count(*) FROM checklist_storage.runs WHERE operator_role = 'checklist_south'"
                ).fetchone()[0],
                0,
            )
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                connection.execute(
                    "UPDATE checklist_storage.completions SET note = 'edited'"
                )
            connection.rollback()
        with owner() as connection:
            count = connection.execute(
                "SELECT count(*) FROM checklist_storage.runs WHERE operator_role = 'checklist_south'"
            ).fetchone()[0]
            connection.execute(
                """INSERT INTO checklist_storage.runs
                (operator_role, request_id, start_payload, start_result, template_id, template_version,
                 template_title, template_snapshot, label, total_steps)
                SELECT 'checklist_south', gen_random_uuid(), '{}', '{}', t.id, t.version,
                t.title, t.steps, 'quota-fixture', jsonb_array_length(t.steps)
                FROM checklist_storage.templates t CROSS JOIN generate_series(1, %s)
                WHERE t.id = %s""",
                (100 - count, TEMPLATE),
            )
        try:
            payload = {
                "p_request_id": str(uuid.uuid4()),
                "p_template_id": TEMPLATE,
                "p_label": "Above quota",
            }
            self.assertEqual(call("rpc/start_run", self.south, payload)[0], 409)
        finally:
            with owner() as connection:
                connection.execute(
                    "DELETE FROM checklist_storage.runs WHERE label = 'quota-fixture'"
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
