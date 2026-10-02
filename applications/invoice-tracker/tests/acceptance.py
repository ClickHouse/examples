import concurrent.futures
import copy
import json
import os
import re
import subprocess
import threading
import time
import unittest
import uuid
from pathlib import Path

import psycopg
import requests
from psycopg.types.json import Jsonb

BASE = "http://127.0.0.1:8000"


def connect(migrator=False):
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_DATABASE", "postgres"),
        user="invoice_migrator" if migrator else os.environ["DB_USERNAME"],
        password=(
            os.environ["TEST_MIGRATOR_PASSWORD"]
            if migrator
            else os.environ["DB_PASSWORD"]
        ),
        sslmode="verify-full",
        sslrootcert=os.environ["DB_SSLROOTCERT"],
        autocommit=True,
        options="-c search_path=invoice_tracker,public",
    )


class Client:
    def __init__(self, email):
        self.session = requests.Session()
        page = self.session.get(BASE + "/login", timeout=20)
        token = re.search(r'name="_token" value="([^"]+)"', page.text).group(1)
        response = self.session.post(
            BASE + "/login",
            data={
                "email": email,
                "password": os.environ["DEMO_PASSWORD"],
                "_token": token,
            },
            allow_redirects=False,
            timeout=20,
        )
        assert response.status_code == 303, response.status_code
        self.token = re.search(
            r'name="_token" value="([^"]+)"',
            self.session.get(BASE + "/invoices", timeout=20).text,
        ).group(1)

    def get(self, path):
        return self.session.get(BASE + path, allow_redirects=False, timeout=20)

    def send(self, path, data=None, method="POST", csrf=True):
        values = dict(data or {})
        if csrf:
            values["_token"] = self.token
        return self.session.request(
            method,
            BASE + path,
            data=values,
            headers={"Accept": "application/json"},
            allow_redirects=False,
            timeout=20,
        )

    def fork(self):
        other = object.__new__(Client)
        other.session = requests.Session()
        other.session.cookies = copy.copy(self.session.cookies)
        other.token = self.token
        return other


class Acceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.prefix = "acceptance-" + uuid.uuid4().hex[:12]
        cls.db = connect()
        cls.migration = connect(True)
        digest = cls.migration.execute(
            "SELECT password FROM users WHERE email='alex@example.test'"
        ).fetchone()[0]
        cls.ids = []
        for name in ["A", "B"]:
            email = f"{cls.prefix}-{name.lower()}@example.test"
            identity = cls.migration.execute(
                "INSERT INTO users(name,email,password,created_at,updated_at) VALUES(%s,%s,%s,now(),now()) RETURNING id",
                [name, email, digest],
            ).fetchone()[0]
            cls.ids.append(identity)
        cls.a = Client(f"{cls.prefix}-a@example.test")
        cls.b = Client(f"{cls.prefix}-b@example.test")

    @classmethod
    def tearDownClass(cls):
        # Dedicated test service only; owner disables history guard inside the cleanup transaction.
        with cls.migration.transaction():
            cls.migration.execute(
                "ALTER TABLE invoice_lines DISABLE TRIGGER draft_invoice_lines"
            )
            cls.migration.execute(
                "DELETE FROM invoice_lines WHERE invoice_id IN (SELECT id FROM invoices WHERE user_id=ANY(%s))",
                [cls.ids],
            )
            cls.migration.execute(
                "DELETE FROM invoices WHERE user_id=ANY(%s)", [cls.ids]
            )
            cls.migration.execute(
                "DELETE FROM sessions WHERE user_id=ANY(%s)", [cls.ids]
            )
            cls.migration.execute("DELETE FROM users WHERE id=ANY(%s)", [cls.ids])
            cls.migration.execute(
                "ALTER TABLE invoice_lines ENABLE TRIGGER draft_invoice_lines"
            )
        cls.db.close()
        cls.migration.close()

    def data(self, reference="Exact services", price="0.10", quantity=3):
        return {
            "recipient": "North Coast Studio",
            "reference": reference,
            "lines[0][description]": "Design hours",
            "lines[0][quantity]": str(quantity),
            "lines[0][unit_price]": price,
        }

    def create(self, **kwargs):
        response = self.a.send("/invoices", self.data(**kwargs))
        self.assertEqual(response.status_code, 303, response.text)
        return int(re.search(r"/invoices/(\d+)", response.headers["Location"]).group(1))

    def row(self, identity):
        with self.db.cursor(row_factory=psycopg.rows.dict_row) as cursor:
            cursor.execute("SELECT * FROM invoices WHERE id=%s", [identity])
            return cursor.fetchone()

    def lines(self, identity):
        return self.db.execute(
            "SELECT description,quantity,unit_cents,position FROM invoice_lines WHERE invoice_id=%s ORDER BY position",
            [identity],
        ).fetchall()

    def issue(self, identity):
        response = self.a.send(f"/invoices/{identity}/issue")
        self.assertEqual(response.status_code, 303, response.text)
        return self.row(identity)

    def simultaneous(self, operations):
        barrier = threading.Barrier(len(operations))

        def run(operation):
            barrier.wait()
            return operation()

        with concurrent.futures.ThreadPoolExecutor(max_workers=len(operations)) as pool:
            return list(pool.map(run, operations))

    def test_authentication_csrf_and_logout_revocation(self):
        anonymous = requests.get(BASE + "/invoices", allow_redirects=False, timeout=20)
        self.assertEqual(anonymous.status_code, 302)
        self.assertEqual(
            self.a.send("/invoices", self.data(), csrf=False).status_code, 419
        )
        temporary = self.a.fork()
        stolen = temporary.fork()
        self.assertEqual(temporary.send("/logout").status_code, 303)
        self.assertEqual(stolen.get("/invoices").status_code, 302)
        # Reauthenticate for following tests after intentionally revoking the shared session.
        type(self).a = Client(f"{self.prefix}-a@example.test")

    def test_create_uses_server_identity_and_exact_usd_total(self):
        data = self.data()
        data.update(
            {
                "user_id": str(self.ids[1]),
                "status": "settled",
                "public_number": "FAKE",
                "lines[1][description]": "Hosting",
                "lines[1][quantity]": "2",
                "lines[1][unit_price]": "12.30",
            }
        )
        response = self.a.send("/invoices", data)
        self.assertEqual(response.status_code, 303)
        identity = int(response.headers["Location"].rsplit("/", 1)[1])
        row = self.row(identity)
        self.assertEqual(row["user_id"], self.ids[0])
        self.assertEqual(row["status"], "draft")
        self.assertIsNone(row["public_number"])
        issued = self.issue(identity)
        self.assertEqual(issued["issued_total_cents"], 2490)
        self.assertIn("$24.90", self.a.get(f"/invoices/{identity}").text)

    def test_cross_user_read_and_mutations_deny(self):
        identity = self.create()
        self.assertEqual(self.a.get("/invoices/not-an-id").status_code, 404)
        for suffix in ["", "/edit"]:
            self.assertEqual(
                self.b.get(f"/invoices/{identity}{suffix}").status_code, 404
            )
        for suffix in ["/issue", "/settle"]:
            self.assertEqual(
                self.b.send(f"/invoices/{identity}{suffix}").status_code, 404
            )
        self.assertEqual(
            self.b.send(f"/invoices/{identity}", self.data(), method="PUT").status_code,
            404,
        )
        self.assertNotIn(f'href="/invoices/{identity}"', self.b.get("/invoices").text)

    def test_invalid_amount_quantity_and_blank_draft_rollback(self):
        before = self.db.execute(
            "SELECT count(*) FROM invoices WHERE user_id=%s", [self.ids[0]]
        ).fetchone()[0]
        for price in ["0.001", "1e3", "-1.00", "1000000.01"]:
            self.assertEqual(
                self.a.send("/invoices", self.data(price=price)).status_code, 422
            )
        self.assertEqual(
            self.a.send("/invoices", self.data(quantity=1001)).status_code, 422
        )
        data = self.data()
        data["lines[0][description]"] = "  "
        self.assertEqual(self.a.send("/invoices", data).status_code, 422)
        self.assertEqual(
            self.db.execute(
                "SELECT count(*) FROM invoices WHERE user_id=%s", [self.ids[0]]
            ).fetchone()[0],
            before,
        )

    def test_competing_issue_and_retry_preserve_one_number_snapshot(self):
        identity = self.create()
        clients = [self.a.fork(), self.a.fork()]
        responses = self.simultaneous(
            [
                lambda client=client: client.send(f"/invoices/{identity}/issue")
                for client in clients
            ]
        )
        self.assertEqual([r.status_code for r in responses], [303, 303])
        original = self.row(identity)
        number = self.db.execute(
            "SELECT last_value FROM invoice_public_number"
        ).fetchone()[0]
        self.issue(identity)
        again = self.row(identity)
        for field in ["public_number", "snapshot", "issued_total_cents", "issued_at"]:
            self.assertEqual(again[field], original[field])
        self.assertEqual(
            self.db.execute("SELECT last_value FROM invoice_public_number").fetchone()[
                0
            ],
            number,
        )

    def test_coordinated_edit_versus_issue_has_whole_snapshot(self):
        identity = self.create()
        clients = [self.a.fork(), self.a.fork()]
        changed = self.data(reference="Edited atomically", price="0.21", quantity=2)
        changed.update(
            {
                "lines[1][description]": "Extra detail",
                "lines[1][quantity]": "1",
                "lines[1][unit_price]": "1.00",
            }
        )
        hold = connect()
        observer = connect()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            with hold.transaction():
                hold.execute(
                    "SELECT id FROM invoices WHERE id=%s FOR UPDATE", [identity]
                )
                barrier = threading.Barrier(2)

                def edit():
                    barrier.wait()
                    return clients[0].send(
                        f"/invoices/{identity}", changed, method="PUT"
                    )

                def issue():
                    barrier.wait()
                    return clients[1].send(f"/invoices/{identity}/issue")

                futures = [pool.submit(edit), pool.submit(issue)]
                deadline = time.monotonic() + 4
                waiting = 0
                while time.monotonic() < deadline:
                    waiting = observer.execute(
                        "SELECT count(*) FROM pg_stat_activity WHERE usename=current_user AND wait_event_type='Lock' AND query ILIKE '%%invoices%%for update%%'"
                    ).fetchone()[0]
                    if waiting >= 2:
                        break
                    time.sleep(0.05)
                self.assertGreaterEqual(
                    waiting,
                    2,
                    "Both real HTTP operations must reach the held parent row lock",
                )
            edit_response, issue_response = [future.result() for future in futures]
        hold.close()
        observer.close()
        self.assertEqual(issue_response.status_code, 303)
        self.assertIn(edit_response.status_code, [303, 409])
        record = self.row(identity)
        if edit_response.status_code == 303:
            self.assertEqual(record["snapshot"]["reference"], "Edited atomically")
            self.assertEqual(record["issued_total_cents"], 142)
            self.assertEqual(len(record["snapshot"]["lines"]), 2)
        else:
            self.assertEqual(record["snapshot"]["reference"], "Exact services")
            self.assertEqual(record["issued_total_cents"], 30)
            self.assertEqual(len(record["snapshot"]["lines"]), 1)
        self.assertEqual(
            self.a.send(f"/invoices/{identity}", changed, method="PUT").status_code, 409
        )

    def test_issue_freezes_rows_and_settlement_is_repeat_safe(self):
        identity = self.create()
        original_lines = self.lines(identity)
        original = self.issue(identity)
        self.assertEqual(self.a.get(f"/invoices/{identity}/edit").status_code, 409)
        self.assertEqual(
            self.a.send(
                f"/invoices/{identity}", self.data(price="1.00"), method="PUT"
            ).status_code,
            409,
        )
        for query in [
            "UPDATE invoices SET issued_total_cents=1 WHERE id=%s",
            "UPDATE invoices SET snapshot='{}'::jsonb WHERE id=%s",
            "UPDATE invoice_lines SET unit_cents=1 WHERE invoice_id=%s",
            "DELETE FROM invoice_lines WHERE invoice_id=%s",
        ]:
            with self.assertRaises(psycopg.errors.CheckViolation):
                self.db.execute(query, [identity])
        self.assertEqual(self.lines(identity), original_lines)
        self.assertEqual(self.a.send(f"/invoices/{identity}/settle").status_code, 303)
        settled = self.row(identity)
        self.assertEqual(settled["status"], "settled")
        self.assertEqual(self.a.send(f"/invoices/{identity}/settle").status_code, 303)
        self.assertEqual(self.row(identity)["settled_at"], settled["settled_at"])
        for field in ["public_number", "snapshot", "issued_total_cents", "issued_at"]:
            self.assertEqual(settled[field], original[field])

    def test_failed_line_insert_rolls_back_header_and_all_old_lines(self):
        identity = self.create()
        before = self.row(identity)
        before_lines = self.lines(identity)
        result = subprocess.run(
            ["php", "tests/probe.php", "rollback", str(self.ids[0]), str(identity)],
            capture_output=True,
            text=True,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.row(identity), before)
        self.assertEqual(self.lines(identity), before_lines)

    def test_database_rejects_null_issued_total_and_duplicate_number(self):
        snapshot = {
            "currency": "USD",
            "recipient": "Test",
            "reference": "Test",
            "lines": [],
        }
        with self.assertRaises(psycopg.errors.CheckViolation):
            self.db.execute(
                "INSERT INTO invoices(user_id,recipient,reference,status,public_number,issued_total_cents,snapshot,issued_at) VALUES(%s,'Test','Test','issued',%s,NULL,%s,now())",
                [self.ids[0], self.prefix, Jsonb(snapshot)],
            )
        first = self.issue(self.create())
        second = self.create()
        with self.assertRaises(psycopg.errors.UniqueViolation):
            self.db.execute(
                "UPDATE invoices SET status='issued',public_number=%s,issued_total_cents=30,snapshot=%s,issued_at=now() WHERE id=%s",
                [first["public_number"], Jsonb(first["snapshot"]), second],
            )
        self.assertEqual(self.row(second)["status"], "draft")

    def test_runtime_role_cannot_change_schema_or_migrations_or_delete_invoice(self):
        identity = self.create()
        for query in [
            "CREATE TABLE invoice_tracker.forbidden(id integer)",
            "UPDATE migrations SET batch=99",
            f"DELETE FROM invoices WHERE id={identity}",
        ]:
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                self.db.execute(query)

    def test_pagination_is_bounded_and_rejects_invalid_page(self):
        marker = self.prefix + "-page"
        self.migration.execute(
            "INSERT INTO invoices(user_id,recipient,reference) SELECT %s,'Page',%s||n FROM generate_series(1,21) n",
            [self.ids[0], marker],
        )
        first = self.a.get("/invoices")
        second = self.a.get("/invoices?page=2")
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.text.count(marker), 20)
        self.assertEqual(second.text.count(marker), 1)
        self.assertEqual(self.a.get("/invoices?page=0").status_code, 302)

    def test_actual_laravel_pdo_tls_ca_and_hostname_controls(self):
        for mode in ["version", "tls-ca", "tls-host"]:
            result = subprocess.run(
                ["php", "tests/probe.php", mode],
                capture_output=True,
                text=True,
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            print(result.stdout.strip())

    def test_database_outage_returns_plain_503(self):
        env = os.environ.copy()
        env.update(
            {"DB_HOST": "127.0.0.1", "DB_PORT": "1", "APP_URL": "http://127.0.0.1:8100"}
        )
        with Path(".deployment/outage-server.log").open("w") as log:
            process = subprocess.Popen(
                ["php", "-S", "127.0.0.1:8100", "-t", "public", "server.php"],
                env=env,
                stdout=log,
                stderr=log,
            )
            try:
                for _ in range(40):
                    try:
                        response = requests.get(
                            "http://127.0.0.1:8100/login", timeout=5
                        )
                        break
                    except requests.ConnectionError:
                        time.sleep(0.05)
                else:
                    self.fail("Outage probe server did not start")
                self.assertEqual(response.status_code, 503)
                self.assertEqual(
                    response.text, "The database is busy. Please try again shortly."
                )
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
