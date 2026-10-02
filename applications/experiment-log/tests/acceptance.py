"""Opt-in real Cloud + running HTTP API acceptance; never run in CI."""

import copy
import json
import os
import time
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

import httpx
import psycopg
from psycopg.types.json import Jsonb

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8080")
A = "00000000-0000-4000-8000-000000000001"
B = "00000000-0000-4000-8000-000000000002"


def connection(owner=False):
    return psycopg.connect(
        host=os.environ["PGHOST"],
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "postgres"),
        user=os.environ["TEST_OWNER_USER"] if owner else os.environ["PGUSER"],
        password=os.environ["TEST_OWNER_PASSWORD"]
        if owner
        else os.environ["PGPASSWORD"],
        sslmode="verify-full",
        sslrootcert=os.environ["PGSSLROOTCERT"],
        connect_timeout=10,
        options="-c statement_timeout=10000 -c lock_timeout=8000",
    )


def request(method, path, data=None, project="A", raw=None):
    with httpx.Client(base_url=BASE, timeout=35) as client:
        headers = {"Authorization": "Bearer " + os.environ[f"PROJECT_{project}_TOKEN"]}
        if raw is not None:
            headers["Content-Type"] = "application/json"
            return client.request(method, path, content=raw, headers=headers)
        return client.request(method, path, json=data, headers=headers)


def payload(title="Synthetic optimizer comparison", config=None):
    return {
        "requestId": str(uuid.uuid4()),
        "title": title,
        "config": {"optimizer": "adam", "enabled": True, "rate": 0.000001}
        if config is None
        else config,
        "measurements": [
            {"name": "accuracy", "value": "0.123456"},
            {"name": "loss", "value": "-0.000001"},
        ],
    }


class CloudAcceptance(unittest.TestCase):
    def create(self, body=None, project="A"):
        body = payload() if body is None else body
        response = request("POST", "/runs", body, project)
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    def test_01_exact_decimal_and_project_scope(self):
        body = payload()
        body["measurements"] += [
            {"name": "minimum", "value": "-1000000"},
            {"name": "maximum", "value": "1000000"},
        ]
        saved = self.create(body)
        values = {m["name"]: m["value"] for m in saved["measurements"]}
        self.assertEqual(
            values,
            {
                "accuracy": "0.123456",
                "loss": "-0.000001",
                "minimum": "-1000000",
                "maximum": "1000000",
            },
        )
        self.assertEqual(
            json.loads(json.dumps(saved), parse_float=Decimal)["config"]["rate"],
            Decimal("0.000001"),
        )
        self.assertEqual(request("GET", "/runs/" + saved["id"]).json(), saved)
        self.assertEqual(
            request("GET", "/runs/" + saved["id"], project="B").status_code, 404
        )
        other = self.create(body, "B")
        self.assertNotEqual(other["id"], saved["id"])
        self.assertEqual(request("GET", "/project", project="B").json(), {"id": B})
        self.assertEqual(httpx.get(BASE + "/project").status_code, 401)
        self.assertEqual(
            httpx.get(
                BASE + "/project", headers={"Authorization": "Bearer wrong"}
            ).status_code,
            401,
        )
        self.assertEqual(request("GET", "/runs/not-a-uuid").status_code, 422)

    def test_02_semantic_replay_and_conflict(self):
        body = payload(config={"b": True, "a": 1})
        body["measurements"][0]["value"] = "1.000000"
        saved = self.create(body)
        reordered = copy.deepcopy(body)
        reordered["config"] = {"a": 1.0, "b": True}
        reordered["measurements"].reverse()
        next(m for m in reordered["measurements"] if m["name"] == "accuracy")[
            "value"
        ] = "1.0"
        response = request("POST", "/runs", reordered)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), saved)
        reordered["title"] += " changed"
        self.assertEqual(request("POST", "/runs", reordered).status_code, 409)

    def test_03_http_boundaries(self):
        for change in [
            {"projectId": A},
            {"config": {"x": None}},
            {"config": {"x": []}},
            {"config": {"x": {}}},
            {"config": {"rate": 0.0000001}},
            {"title": "\u0085bad"},
            {"title": "\ud800"},
            {"measurements": [{"name": "metric", "value": "0.1234567"}]},
            {"measurements": [{"name": "metric", "value": "1e3"}]},
            {"measurements": [{"name": "metric", "value": 1}]},
            {"measurements": []},
        ]:
            body = payload()
            body.update(change)
            self.assertEqual(
                request("POST", "/runs", raw=json.dumps(body).encode()).status_code,
                422,
                str(change),
            )
        malformed = [b'{"x":1,"x":2}', b"\xff"]
        for raw in malformed:
            self.assertEqual(request("POST", "/runs", raw=raw).status_code, 400)
        out_of_bounds = [b'{"x":1e999999}', b'{"x":[[[[[1]]]]]}', b" " * 16385]
        for raw in out_of_bounds:
            self.assertEqual(request("POST", "/runs", raw=raw).status_code, 422)
        body = payload(config={"x": 0.000001})
        self.create(body)

    def competing(self, conflicting):
        first = payload()
        second = copy.deepcopy(first)
        if conflicting:
            second["title"] += " other"
        with connection(True) as owner:
            owner.execute("LOCK TABLE experiment_log.runs IN SHARE ROW EXCLUSIVE MODE")
            with ThreadPoolExecutor(max_workers=2) as pool:
                calls = [
                    pool.submit(request, "POST", "/runs", body)
                    for body in [first, second]
                ]
                deadline = time.monotonic() + 5
                blocked = 0
                while time.monotonic() < deadline:
                    owner.execute("SELECT pg_stat_clear_snapshot()")
                    blocked = owner.execute(
                        "SELECT count(*) FROM pg_stat_activity WHERE usename='experiment_app' AND cardinality(pg_blocking_pids(pid)) > 0"
                    ).fetchone()[0]
                    if blocked >= 2:
                        break
                    time.sleep(0.05)
                self.assertGreaterEqual(
                    blocked,
                    2,
                    "both independent HTTP transactions must contend on a real DB lock",
                )
                owner.commit()
                responses = [call.result() for call in calls]
        self.assertEqual(
            sorted(r.status_code for r in responses),
            [201, 409] if conflicting else [200, 201],
        )
        success = next(r.json() for r in responses if r.status_code == 201)
        if not conflicting:
            self.assertEqual(responses[0].json(), responses[1].json())
        with connection(True) as owner:
            self.assertEqual(
                owner.execute(
                    "SELECT count(*) FROM experiment_log.runs WHERE project_id=%s AND request_id=%s",
                    (A, first["requestId"]),
                ).fetchone()[0],
                1,
            )
            self.assertEqual(
                owner.execute(
                    "SELECT count(*) FROM experiment_log.measurements WHERE run_id=%s",
                    (success["id"],),
                ).fetchone()[0],
                2,
            )

    def test_04_competing_matching_retained_request(self):
        self.competing(False)

    def test_05_competing_conflicting_retained_request(self):
        self.competing(True)

    def test_06_after_parent_and_first_child_rollback(self):
        body = payload()
        body["measurements"] = [
            {"name": "a_first", "value": "1"},
            {"name": "z_forced_failure", "value": "2"},
        ]
        with connection(True) as owner:
            owner.execute("""CREATE FUNCTION experiment_log.acceptance_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
                IF NEW.name='z_forced_failure' AND EXISTS (SELECT 1 FROM experiment_log.measurements WHERE run_id=NEW.run_id AND name='a_first') THEN
                    RAISE EXCEPTION 'Controlled child failure' USING ERRCODE='23514'; END IF; RETURN NEW; END $$""")
            owner.execute(
                "CREATE TRIGGER acceptance_fault AFTER INSERT ON experiment_log.measurements FOR EACH ROW EXECUTE FUNCTION experiment_log.acceptance_fault()"
            )
        try:
            response = request("POST", "/runs", body)
            self.assertEqual(response.status_code, 503, response.text)
            with connection(True) as owner:
                self.assertEqual(
                    owner.execute(
                        "SELECT count(*) FROM experiment_log.runs WHERE request_id=%s",
                        (body["requestId"],),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    owner.execute(
                        "SELECT count(*) FROM experiment_log.measurements m JOIN experiment_log.runs r ON r.id=m.run_id AND r.project_id=m.project_id WHERE r.request_id=%s",
                        (body["requestId"],),
                    ).fetchone()[0],
                    0,
                )
        finally:
            with connection(True) as owner:
                owner.execute(
                    "DROP TRIGGER acceptance_fault ON experiment_log.measurements"
                )
                owner.execute("DROP FUNCTION experiment_log.acceptance_fault()")
        self.create(body)

    def test_07_immutable_role_and_initial_transaction(self):
        saved = self.create()
        denied = [
            "UPDATE experiment_log.runs SET title='changed'",
            "DELETE FROM experiment_log.runs",
            "CREATE TABLE experiment_log.forbidden(id int)",
            "CREATE TEMP TABLE forbidden(id int)",
        ]
        for statement in denied:
            with connection() as runtime:
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    runtime.execute(statement)
        with connection() as runtime:
            with self.assertRaises(psycopg.errors.CheckViolation):
                runtime.execute(
                    "INSERT INTO experiment_log.measurements(project_id,run_id,name,value) VALUES(%s,%s,'late',1)",
                    (A, saved["id"]),
                )
        self.assertEqual(request("GET", "/runs/" + saved["id"]).json(), saved)

    def test_08_database_complete_set_and_no_numeric_rounding(self):
        body = payload()
        semantic = {
            "title": body["title"],
            "config": body["config"],
            "measurements": {"accuracy": "0.123456", "loss": "-0.000001"},
        }
        with connection() as runtime:
            with self.assertRaises(psycopg.errors.CheckViolation):
                runtime.execute(
                    "INSERT INTO experiment_log.runs(id,project_id,request_id,title,config,request_payload) VALUES(%s,%s,%s,%s,%s,%s)",
                    (
                        uuid.uuid4(),
                        A,
                        body["requestId"],
                        body["title"],
                        Jsonb(body["config"]),
                        Jsonb(semantic),
                    ),
                )
                runtime.commit()
        with connection(True) as owner:
            self.assertEqual(
                owner.execute(
                    "SELECT count(*) FROM experiment_log.runs WHERE request_id=%s",
                    (body["requestId"],),
                ).fetchone()[0],
                0,
            )
        with connection(True) as owner:
            run_id = uuid.uuid4()
            owner.execute(
                "INSERT INTO experiment_log.runs(id,project_id,request_id,title,config,request_payload) VALUES(%s,%s,%s,%s,%s,%s)",
                (
                    run_id,
                    A,
                    uuid.uuid4(),
                    body["title"],
                    Jsonb(body["config"]),
                    Jsonb(semantic),
                ),
            )
            with self.assertRaises(psycopg.errors.CheckViolation):
                owner.execute(
                    "INSERT INTO experiment_log.measurements(project_id,run_id,name,value) VALUES(%s,%s,'accuracy',0.1234567)",
                    (A, run_id),
                )

    def test_09_jsonb_literal_search_and_keyset(self):
        marker = uuid.uuid4().hex
        created = [
            self.create(
                payload(
                    f"{marker} literal%_ item {i}",
                    {"suite": marker, "optimizer": "adam", "enabled": True},
                )
            )
            for i in range(5)
        ]
        first = request(
            "POST",
            "/runs/search",
            {"config": {"suite": marker, "enabled": True}, "title": "%_", "limit": 2},
        )
        self.assertEqual(first.status_code, 200, first.text)
        seen = []
        cursor = None
        for _ in range(4):
            fields = {"config": {"suite": marker}, "limit": 2}
            if cursor:
                fields["cursor"] = cursor
            response = request("POST", "/runs/search", fields)
            self.assertEqual(response.status_code, 200, response.text)
            data = response.json()
            seen.extend(row["id"] for row in data["runs"])
            cursor = data["nextCursor"]
            if cursor is None:
                break
        self.assertEqual(len(seen), 5)
        self.assertEqual(set(seen), {row["id"] for row in created})
        self.assertEqual(
            request(
                "POST", "/runs/search", {"config": {"suite": marker, "enabled": False}}
            ).json()["runs"],
            [],
        )
        empty_filter = request(
            "POST", "/runs/search", {"config": {}, "limit": 20}
        ).json()
        self.assertGreater(len(empty_filter["runs"]), 0)
        self.assertLessEqual(len(empty_filter["runs"]), 20)
        for fields in [
            {"limit": 21},
            {"cursor": "invalid"},
            {"config": []},
            {"config": {"x": None}},
        ]:
            self.assertEqual(request("POST", "/runs/search", fields).status_code, 422)
        other = request(
            "POST", "/runs/search", {"config": {"suite": marker}}, project="B"
        )
        self.assertEqual(other.json()["runs"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
