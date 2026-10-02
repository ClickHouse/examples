"""Run only against this example's dedicated Cloud database; migrator cleans owned fixtures."""

import os
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor

import psycopg
from sqlalchemy import event, text
from sqlalchemy.exc import DBAPIError
from unittest.mock import patch

from reviewdesk.database import make_engine
from reviewdesk.service import approve_batch, create_batch, get_batch, save_rows
from reviewdesk.validation import HEADERS, ReviewError


class CloudAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = make_engine()
        cls.batch_ids = []
        cls.prefix = "T" + uuid.uuid4().hex[:10].upper()
        with cls.engine.connect() as conn:
            print("Postgres", conn.scalar(text("SELECT version()")))
            print("Runtime", conn.scalar(text("SELECT current_user")))

    @classmethod
    def tearDownClass(cls):
        # This cleanup authority is never passed to the Streamlit server.
        if cls.batch_ids:
            with psycopg.connect(
                user="csv_migrator",
                password=os.environ["TEST_MIGRATOR_PASSWORD"],
                options="-c search_path=csv_review,public",
                sslmode="verify-full",
            ) as conn:
                conn.execute("ALTER TABLE staged_rows DISABLE TRIGGER staged_guard")
                conn.execute(
                    "DELETE FROM catalogue_items WHERE source_batch_id = ANY(%s)", (cls.batch_ids,)
                )
                conn.execute("DELETE FROM staged_rows WHERE batch_id = ANY(%s)", (cls.batch_ids,))
                conn.execute("DELETE FROM batches WHERE id = ANY(%s)", (cls.batch_ids,))
                conn.execute("ALTER TABLE staged_rows ENABLE TRIGGER staged_guard")
        cls.engine.dispose()

    def batch(self, suffix, rows):
        csv = (
            "sku,name,price_cents\n"
            + "\n".join(f"{self.prefix}-{suffix}-{sku},{name},{price}" for sku, name, price in rows)
            + "\n"
        )
        batch_id = create_batch(self.engine, suffix + ".csv", csv.encode())
        self.batch_ids.append(uuid.UUID(batch_id))
        return get_batch(self.engine, batch_id)

    def payload(self, batch):
        return [{key: row[key] for key in ["id", *HEADERS]} for row in batch["rows"]]

    def count(self, batch_id):
        with self.engine.connect() as conn:
            return conn.scalar(
                text("SELECT count(*) FROM catalogue_items WHERE source_batch_id=:id"),
                {"id": uuid.UUID(batch_id)},
            )

    def outcome(self, action):
        try:
            return ("ok", action())
        except ReviewError as exc:
            return ("rejected", str(exc))

    def wait_for_two_locks(self):
        deadline = time.monotonic() + 7
        while time.monotonic() < deadline:
            with self.engine.connect() as conn:
                count = conn.scalar(
                    text(
                        "SELECT count(*) FROM pg_stat_activity WHERE usename=current_user AND wait_event_type='Lock' AND query ILIKE '%batches%'"
                    )
                )
            if count >= 2:
                return
            time.sleep(0.1)
        self.fail("Both independent transactions must be observed waiting for the held parent row")

    def test_invalid_rows_correction_stable_identity_exact_price(self):
        batch = self.batch("CORRECT", [("A", "", "3.50"), ("A", "Notebook", "350")])
        ids = [r["id"] for r in batch["rows"]]
        self.assertTrue(all(r["errors"] for r in batch["rows"]))
        rows = self.payload(batch)
        rows[0].update(name="Notebook", price_cents="350")
        rows[1]["sku"] += "-SECOND"
        corrected = save_rows(self.engine, batch["id"], 1, list(reversed(rows)))
        self.assertEqual([r["id"] for r in corrected["rows"]], ids)
        self.assertFalse(any(r["errors"] for r in corrected["rows"]))
        result = approve_batch(self.engine, batch["id"], 2)
        self.assertEqual(result["published_rows"], 2)
        with self.engine.connect() as conn:
            self.assertEqual(
                conn.scalar(
                    text("SELECT sum(price_cents) FROM catalogue_items WHERE source_batch_id=:id"),
                    {"id": uuid.UUID(batch["id"])},
                ),
                700,
            )

    def test_stale_save_and_forged_row_identity_rejected(self):
        batch = self.batch("STALE", [("A", "Original", "10")])
        payload = self.payload(batch)
        payload[0]["name"] = "Committed"
        save_rows(self.engine, batch["id"], 1, payload)
        payload[0]["name"] = "Stale overwrite"
        with self.assertRaisesRegex(ReviewError, "changed"):
            save_rows(self.engine, batch["id"], 1, payload)
        with self.assertRaisesRegex(ReviewError, "changed"):
            approve_batch(self.engine, batch["id"], 1)
        payload[0]["id"] = str(uuid.uuid4())
        with self.assertRaisesRegex(ReviewError, "identities"):
            save_rows(self.engine, batch["id"], 2, payload)
        self.assertEqual(get_batch(self.engine, batch["id"])["rows"][0]["name"], "Committed")
        self.assertEqual(self.count(batch["id"]), 0)

    def test_simultaneous_approvals_return_original_result(self):
        batch = self.batch("RACE", [("A", "One", "10"), ("B", "Two", "20")])
        barrier = threading.Barrier(3)

        def action():
            barrier.wait()
            return approve_batch(self.engine, batch["id"], 1)

        with ThreadPoolExecutor(max_workers=2) as pool:
            with self.engine.begin() as holder:
                holder.execute(
                    text("SELECT id FROM batches WHERE id=:id FOR UPDATE"),
                    {"id": uuid.UUID(batch["id"])},
                )
                futures = [pool.submit(action) for _ in range(2)]
                barrier.wait()
                self.wait_for_two_locks()
            results = [future.result(timeout=25) for future in futures]
        self.assertEqual(results[0], results[1])
        self.assertEqual(self.count(batch["id"]), 2)
        self.assertEqual(approve_batch(self.engine, batch["id"], 1), results[0])

    def test_edit_versus_approve_ordering(self):
        batch = self.batch("ORDER", [("A", "Before", "10")])
        payload = self.payload(batch)
        payload[0].update(name="After", price_cents="99")
        barrier = threading.Barrier(3)

        def save():
            barrier.wait()
            return self.outcome(lambda: save_rows(self.engine, batch["id"], 1, payload))

        def approve():
            barrier.wait()
            return self.outcome(lambda: approve_batch(self.engine, batch["id"], 1))

        with ThreadPoolExecutor(max_workers=2) as pool:
            with self.engine.begin() as holder:
                holder.execute(
                    text("SELECT id FROM batches WHERE id=:id FOR UPDATE"),
                    {"id": uuid.UUID(batch["id"])},
                )
                edit_future, approve_future = pool.submit(save), pool.submit(approve)
                barrier.wait()
                self.wait_for_two_locks()
            edit, approval = edit_future.result(timeout=25), approve_future.result(timeout=25)
        self.assertEqual(sorted([edit[0], approval[0]]), ["ok", "rejected"])
        current = get_batch(self.engine, batch["id"])
        if approval[0] == "ok":
            self.assertEqual(current["status"], "approved")
            self.assertEqual(current["rows"][0]["name"], "Before")
            self.assertEqual(self.count(batch["id"]), 1)
        else:
            self.assertEqual(current["status"], "pending")
            self.assertEqual(current["rows"][0]["name"], "After")
            self.assertEqual(self.count(batch["id"]), 0)

    def test_catalogue_conflict_after_validation_rolls_back_all(self):
        batch = self.batch("LATE", [("A", "New", "10"), ("Z", "Shared", "20")])
        other = self.batch("WINNER", [("Z", "Winner", "99")])
        rows = self.payload(other)
        rows[0]["sku"] = batch["rows"][1]["sku"]
        save_rows(self.engine, other["id"], 1, rows)
        paused, release = threading.Event(), threading.Event()
        competitor_engine = make_engine()

        def pause_insert(conn, cursor, statement, parameters, context, executemany):
            if statement.startswith("INSERT INTO catalogue_items"):
                paused.set()
                if not release.wait(30):
                    raise AssertionError("Competing publication did not release insert")

        event.listen(self.engine, "before_cursor_execute", pause_insert)
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(
                    self.outcome, lambda: approve_batch(self.engine, batch["id"], 1)
                )
                self.assertTrue(
                    paused.wait(30), "Approval reached insert after its validation read"
                )
                approve_batch(competitor_engine, other["id"], 2)
                release.set()
                outcome = future.result(timeout=25)
            self.assertEqual(outcome[0], "rejected")
            self.assertIn("SKU conflict", outcome[1])
        finally:
            release.set()
            event.remove(self.engine, "before_cursor_execute", pause_insert)
            competitor_engine.dispose()
        self.assertEqual(self.count(batch["id"]), 0)
        self.assertEqual(get_batch(self.engine, batch["id"])["status"], "pending")
        with self.engine.connect() as conn:
            self.assertEqual(
                conn.scalar(
                    text("SELECT name FROM catalogue_items WHERE sku=:sku"), {"sku": rows[0]["sku"]}
                ),
                "Winner",
            )

    def test_invalid_approval_feedback_persists_without_partial_publish(self):
        batch = self.batch("INVALID", [("A", "Good", "10"), ("B", "", "1.0")])
        with self.assertRaisesRegex(ReviewError, "correct"):
            approve_batch(self.engine, batch["id"], 1)
        current = get_batch(self.engine, batch["id"])
        self.assertEqual(current["revision"], 2)
        self.assertTrue(current["rows"][1]["errors"])
        self.assertEqual(self.count(batch["id"]), 0)

    def test_existing_catalogue_validation_and_immutable_approved_rows(self):
        batch = self.batch("EXIST", [("A", "First", "10")])
        approve_batch(self.engine, batch["id"], 1)
        other = self.batch("EXIST2", [("A", "Second", "20")])
        payload = self.payload(other)
        payload[0]["sku"] = batch["rows"][0]["sku"]
        corrected = save_rows(self.engine, other["id"], 1, payload)
        self.assertIn("already exists", corrected["rows"][0]["errors"][0])
        with self.assertRaises(ReviewError):
            save_rows(self.engine, batch["id"], 2, self.payload(batch))
        with self.assertRaises(DBAPIError) as failure, self.engine.begin() as conn:
            conn.execute(
                text("UPDATE staged_rows SET name='Changed' WHERE batch_id=:id"),
                {"id": uuid.UUID(batch["id"])},
            )
        self.assertEqual(failure.exception.orig.sqlstate, "23514")

    def test_database_constraints_and_restricted_runtime(self):
        batch = self.batch("DB", [("A", "One", "10")])
        other = self.batch("DB2", [("A", "Other", "10")])
        with self.assertRaises(DBAPIError) as failure, self.engine.begin() as conn:
            conn.execute(
                text("INSERT INTO catalogue_items VALUES ('MISMATCH','Wrong',1,:batch,:row)"),
                {"batch": uuid.UUID(other["id"]), "row": uuid.UUID(batch["rows"][0]["id"])},
            )
        self.assertEqual(failure.exception.orig.sqlstate, "23503")
        with self.assertRaises(DBAPIError) as failure, self.engine.begin() as conn:
            conn.execute(
                text(
                    "UPDATE batches SET status='approved', approved_at=now(), revision=revision+1 WHERE id=:id"
                ),
                {"id": uuid.UUID(batch["id"])},
            )
        self.assertEqual(failure.exception.orig.sqlstate, "23514")
        for sql in [
            "CREATE TABLE csv_review.forbidden(id integer)",
            "CREATE TABLE public.forbidden(id integer)",
            "SELECT * FROM csv_review.alembic_version",
            "DELETE FROM catalogue_items",
            "UPDATE catalogue_items SET name='Changed'",
        ]:
            with (
                self.subTest(sql=sql),
                self.assertRaises(DBAPIError) as failure,
                self.engine.begin() as conn,
            ):
                conn.execute(text(sql))
            self.assertEqual(failure.exception.orig.sqlstate, "42501")

    def test_driver_tls_verification(self):
        with self.engine.connect() as conn:
            self.assertTrue(
                conn.scalar(text("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()"))
            )
        with tempfile.TemporaryDirectory() as directory:
            ca = directory + "/wrong.pem"
            subprocess.run(
                [
                    "openssl",
                    "req",
                    "-x509",
                    "-newkey",
                    "rsa:2048",
                    "-nodes",
                    "-days",
                    "1",
                    "-subj",
                    "/CN=Wrong CA",
                    "-keyout",
                    directory + "/key",
                    "-out",
                    ca,
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            with patch.dict(os.environ, {"PGSSLROOTCERT": ca}):
                wrong = make_engine()
                try:
                    with self.assertRaises(DBAPIError) as failure:
                        wrong.connect()
                    self.assertIn("certificate verify failed", str(failure.exception.orig))
                finally:
                    wrong.dispose()
        hostaddr = socket.gethostbyname(os.environ["PGHOST"])
        with self.assertRaises(psycopg.OperationalError) as failure:
            psycopg.connect(
                host="hostname-mismatch.invalid",
                hostaddr=hostaddr,
                user=os.environ["PGUSER"],
                password=os.environ["PGPASSWORD"],
                dbname=os.environ["PGDATABASE"],
                sslmode="verify-full",
                sslrootcert=os.environ["PGSSLROOTCERT"],
                connect_timeout=10,
            )
        self.assertRegex(str(failure.exception), "certificate.*does not match host name")


if __name__ == "__main__":
    unittest.main(verbosity=2)
