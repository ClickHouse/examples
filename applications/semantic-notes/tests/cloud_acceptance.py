"""Real Cloud/model controls. Run only against your dedicated example service."""

import concurrent.futures
import os
import socket
import threading
import time
import unittest
from uuid import uuid4

import httpx
import numpy as np
import psycopg
from pgvector.psycopg import register_vector

from semantic_notes.database import make_engine
from semantic_notes.embeddings import Encoder
from semantic_notes.service import DomainError, update_note
from semantic_notes.spec import SPEC
from semantic_notes.validation import UpdateInput

ORIGIN = "http://127.0.0.1:8000"


def connection(*, owner=False, **overrides):
    values = {
        "host": os.environ["PGHOST"],
        "port": os.getenv("PGPORT", "5432"),
        "dbname": os.environ["PGDATABASE"],
        "user": os.environ["PGUSER"],
        "password": os.environ["PGPASSWORD"],
        "sslmode": "verify-full",
        "sslrootcert": os.environ["PGSSLROOTCERT"],
        "connect_timeout": 10,
    }
    if owner:
        values.update(
            user=os.environ["TEST_OWNER_USER"],
            password=os.environ["TEST_OWNER_PASSWORD"],
        )
    values.update(overrides)
    conn = psycopg.connect(**values)
    register_vector(conn)
    return conn


def stored(note_id):
    with connection() as conn:
        return conn.execute(
            "SELECT title,body,embedding,revision FROM semantic_notes.notes WHERE id=%s",
            (note_id,),
        ).fetchone()


class CloudAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = httpx.Client(
            base_url=ORIGIN, headers={"Origin": ORIGIN}, timeout=40
        )
        cls.encoder = Encoder()
        cls.ids = []
        examples = [
            (
                "Reading habit",
                "Read a book for twenty minutes every evening and write a short note about what you learned.",
            ),
            (
                "Remembering books",
                "Keep a daily reading journal with a few sentences summarizing the ideas in each chapter.",
            ),
            (
                "Garden watering",
                "Water tomato seedlings early in the morning and check whether the soil is dry before adding more water.",
            ),
        ]
        for title, body in examples:
            response = cls.client.post(
                "/api/notes", json={"title": title, "body": body}
            )
            if response.status_code != 201:
                raise RuntimeError(
                    f"Fixture creation failed: {response.status_code} {response.text}"
                )
            cls.ids.append(response.json()["id"])
        print(
            "Fixture setup: 3 actual CPU-embedded notes (not additional test cases)",
            flush=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.client.close()

    def test_01_exact_cosine_related_fixture_and_independent_comparison(self):
        query = "A daily journal helps me remember the books I read"
        response = self.client.post("/api/search", json={"q": query, "k": 10})
        self.assertEqual(response.status_code, 200)
        results = response.json()["results"]
        vector = self.encoder.embed(query).astype(np.float64)
        with connection() as conn:
            rows = conn.execute(
                "SELECT id,embedding FROM semantic_notes.notes"
            ).fetchall()
        expected = sorted(
            [
                (
                    str(i),
                    float(
                        1
                        - np.dot(v.to_numpy().astype(np.float64), vector)
                        / (
                            np.linalg.norm(v.to_numpy().astype(np.float64))
                            * np.linalg.norm(vector)
                        )
                    ),
                )
                for i, v in rows
            ],
            key=lambda pair: (pair[1], pair[0]),
        )
        self.assertEqual([r["id"] for r in results], [i for i, d in expected[:10]])
        for observed, (_, distance) in zip(results, expected):
            self.assertAlmostEqual(observed["distance"], distance, delta=1e-5)
        distances = {r["id"]: r["distance"] for r in results}
        self.assertLess(distances[self.ids[0]], distances[self.ids[2]])
        self.assertLess(distances[self.ids[1]], distances[self.ids[2]])
        print(
            "Actual fixture ranks/distances:",
            [(r["title"], round(r["distance"], 6)) for r in results],
            flush=True,
        )

    def test_02_revisioned_edit_and_stale_rejection(self):
        note = self.client.get(f"/api/notes/{self.ids[0]}").json()
        fields = {
            "title": "Reading habit updated",
            "body": "Read each evening and keep a short summary in a notebook.",
            "revision": note["revision"],
        }
        response = self.client.put(f"/api/notes/{self.ids[0]}", json=fields)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["revision"], note["revision"] + 1)
        self.assertEqual(
            self.client.put(f"/api/notes/{self.ids[0]}", json=fields).status_code, 409
        )
        saved = stored(self.ids[0])
        np.testing.assert_allclose(
            saved[2].to_numpy(),
            self.encoder.embed(Encoder.document_text(fields["title"], fields["body"])),
            atol=1e-6,
        )

    def test_03_competing_http_updates_observe_database_waits(self):
        note_id = self.ids[1]
        note = self.client.get(f"/api/notes/{note_id}").json()
        lock = connection(owner=True)
        lock.execute(
            "SELECT id FROM semantic_notes.notes WHERE id=%s FOR UPDATE", (note_id,)
        )
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=2)

        def update(label):
            with httpx.Client(
                base_url=ORIGIN, headers={"Origin": ORIGIN}, timeout=40
            ) as client:
                return client.put(
                    f"/api/notes/{note_id}",
                    json={
                        "title": label,
                        "body": "A short reading journal records ideas worth revisiting.",
                        "revision": note["revision"],
                    },
                )

        futures = [
            pool.submit(update, label)
            for label in ["Competing reading A", "Competing reading B"]
        ]
        try:
            waited = False
            with connection(owner=True) as observer:
                for _ in range(100):
                    blocked = observer.execute(
                        "SELECT count(*) FROM pg_stat_activity WHERE usename='semantic_app' AND cardinality(pg_blocking_pids(pid)) > 0"
                    ).fetchone()[0]
                    if blocked >= 2:
                        waited = True
                        break
                    time.sleep(0.1)
            self.assertTrue(
                waited,
                "two independent HTTP transactions must wait behind the held parent row",
            )
            lock.commit()
            responses = [f.result(timeout=40) for f in futures]
            self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
            self.assertEqual(stored(note_id)[3], note["revision"] + 1)
            print(
                "Observed two Cloud row-lock waits; competing HTTP statuses 200/409",
                flush=True,
            )
        finally:
            lock.rollback()
            lock.close()
            pool.shutdown(wait=True)

    def test_04_slow_old_actual_embedding_cannot_overwrite_new_edit(self):
        note_id = self.ids[0]
        note = self.client.get(f"/api/notes/{note_id}").json()
        old = UpdateInput(
            title="Slow older reading edit",
            body="Record an older summary of a book.",
            revision=note["revision"],
        )
        engine = make_engine()
        entered, proceed = threading.Event(), threading.Event()

        def delayed():
            entered.set()
            if not proceed.wait(10):
                raise RuntimeError("test gate timed out")
            vector = self.encoder.embed(Encoder.document_text(old.title, old.body))
            return update_note(engine, note_id, old, vector)

        pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        future = pool.submit(delayed)
        try:
            self.assertTrue(entered.wait(5))
            self.assertEqual(engine.pool.checkedout(), 0)
            newer = {
                "title": "Current reading summary",
                "body": "The newest reading summary is the one to keep.",
                "revision": note["revision"],
            }
            response = self.client.put(f"/api/notes/{note_id}", json=newer)
            self.assertEqual(response.status_code, 200)
            proceed.set()
            with self.assertRaises(DomainError) as conflict:
                future.result(timeout=20)
            self.assertEqual(conflict.exception.status, 409)
            saved = stored(note_id)
            self.assertEqual(saved[:2], (newer["title"], newer["body"]))
            np.testing.assert_allclose(
                saved[2].to_numpy(),
                self.encoder.embed(
                    Encoder.document_text(newer["title"], newer["body"])
                ),
                atol=1e-6,
            )
            print(
                "Coordinated older real CPU job had zero checked-out DB connections; newer HTTP commit survived 409",
                flush=True,
            )
        finally:
            proceed.set()
            pool.shutdown(wait=True)
            engine.dispose()

    def test_05_commit_time_failure_rolls_back_text_vector_and_revision(self):
        note_id = self.ids[2]
        before = stored(note_id)
        with connection(owner=True) as owner:
            owner.execute(
                """CREATE FUNCTION semantic_notes.test_reject_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.title='Rollback marker' THEN RAISE EXCEPTION 'Acceptance commit failure' USING ERRCODE='23514'; END IF; RETURN NEW; END $$"""
            )
            owner.execute(
                "CREATE CONSTRAINT TRIGGER test_reject_commit AFTER UPDATE ON semantic_notes.notes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION semantic_notes.test_reject_commit()"
            )
        try:
            response = self.client.put(
                f"/api/notes/{note_id}",
                json={
                    "title": "Rollback marker",
                    "body": "A changed text creates a different real vector before this commit fails.",
                    "revision": before[3],
                },
            )
            self.assertEqual(response.status_code, 503)
            after = stored(note_id)
            self.assertEqual(after[:2], before[:2])
            self.assertEqual(after[3], before[3])
            np.testing.assert_array_equal(after[2].to_numpy(), before[2].to_numpy())
            print(
                "Owner-only deferred trigger failed after UPDATE; complete text/vector/revision rolled back",
                flush=True,
            )
        finally:
            with connection(owner=True) as owner:
                owner.execute(
                    "DROP TRIGGER test_reject_commit ON semantic_notes.notes; DROP FUNCTION semantic_notes.test_reject_commit()"
                )

    def test_06_origin_token_and_request_bounds(self):
        fields = {"title": "Cross site", "body": "This must not be created."}
        with httpx.Client(base_url=ORIGIN, timeout=40) as foreign:
            self.assertEqual(foreign.post("/api/notes", json=fields).status_code, 403)
            self.assertEqual(
                foreign.post(
                    "/api/notes",
                    json=fields,
                    headers={"Origin": "https://foreign.invalid"},
                ).status_code,
                403,
            )
        self.assertEqual(
            self.client.post(
                "/api/notes", json={"title": "Long", "body": "hello " * 255}
            ).status_code,
            422,
        )
        self.assertEqual(
            self.client.post(
                "/api/notes", json={"title": "Bad", "body": "x", "embedding": [1]}
            ).status_code,
            422,
        )
        self.assertEqual(
            self.client.post("/api/search", json={"q": "read", "k": 11}).status_code,
            422,
        )
        self.assertEqual(
            self.client.post("/api/search", json={"q": "x" * 513}).status_code, 422
        )
        self.assertEqual(
            self.client.post("/api/notes", content=b"x" * 16385).status_code, 413
        )
        self.assertEqual(self.client.get("/api/notes/not-a-uuid").status_code, 422)
        self.assertEqual(self.client.get("/api/notes?page=11").status_code, 422)

    def test_06b_numeric_form_and_unicode_shapes(self):
        fields = {"title": "Valid", "body": "Short body", "revision": "9" * 5000}
        response = self.client.post(f"/notes/{self.ids[0]}", data=fields)
        self.assertEqual(response.status_code, 422)
        self.assertIn("9" * 20, response.text)
        self.assertEqual(
            self.client.post(
                "/search", data={"q": "read", "k": "9" * 5000}
            ).status_code,
            422,
        )
        self.assertEqual(
            self.client.post("/search", data={"q": "read", "k": "two"}).status_code, 422
        )
        self.assertEqual(
            self.client.post(
                "/search",
                content="q=read&k=2&k=3",
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            ).status_code,
            422,
        )
        self.assertEqual(
            self.client.post(
                "/notes",
                content="title=A&title=B&body=Short",
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            ).status_code,
            422,
        )
        for payload in ['{"title":"Bad\\ud800","body":"Short"}', '{"q":"Bad\\ud800"}']:
            path = "/api/notes" if "title" in payload else "/api/search"
            self.assertEqual(
                self.client.post(
                    path, content=payload, headers={"Content-Type": "application/json"}
                ).status_code,
                422,
            )

    def test_07_roles_dimensions_and_fixed_full_collection_spec(self):
        with connection() as runtime:
            runtime.autocommit = True
            for sql in [
                "CREATE SCHEMA forbidden_semantic",
                "ALTER TABLE semantic_notes.notes ADD COLUMN forbidden integer",
                "UPDATE semantic_notes.collection SET spec='{}'::jsonb",
                "DELETE FROM semantic_notes.notes",
            ]:
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    runtime.execute(sql)
            for vector in ["[1,2]", "[" + ",".join(["0"] * 384) + "]"]:
                with self.assertRaises(
                    (psycopg.DataError, psycopg.errors.CheckViolation)
                ):
                    runtime.execute(
                        "INSERT INTO semantic_notes.notes(id,title,body,embedding) VALUES(%s,'Invalid vector','Rejected',%s::vector)",
                        (uuid4(), vector),
                    )
        with connection(owner=True) as owner:
            changed = {**SPEC, "document_format": "body only"}
            from psycopg.types.json import Jsonb

            with self.assertRaises(psycopg.errors.CheckViolation):
                owner.execute(
                    "UPDATE semantic_notes.collection SET spec=%s", (Jsonb(changed),)
                )
        old = os.environ.get("MODEL_REVISION")
        os.environ["MODEL_REVISION"] = "wrong"
        try:
            with self.assertRaisesRegex(ValueError, "fixed model"):
                Encoder()
        finally:
            if old is None:
                os.environ.pop("MODEL_REVISION", None)
            else:
                os.environ["MODEL_REVISION"] = old

    def test_08_database_quota_blocks_the_101st_note(self):
        vector = stored(self.ids[0])[2]
        with connection(owner=True) as owner:
            total = owner.execute(
                "SELECT count(*) FROM semantic_notes.notes"
            ).fetchone()[0]
            for i in range(100 - total):
                owner.execute(
                    "INSERT INTO semantic_notes.notes(id,title,body,embedding) VALUES(%s,%s,'Quota fixture reuses an actual model vector',%s)",
                    (uuid4(), f"Quota {i}", vector),
                )
            with self.assertRaises(psycopg.errors.CheckViolation):
                owner.execute(
                    "INSERT INTO semantic_notes.notes(id,title,body,embedding) VALUES(%s,'Over quota','Must fail',%s)",
                    (uuid4(), vector),
                )
            owner.rollback()
        self.assertEqual(self.client.get("/api/notes").json()["total"], len(self.ids))

    def test_09_tls_certificate_and_actual_hostname_negative_controls(self):
        with self.assertRaises(psycopg.OperationalError) as ca:
            connection(sslrootcert="/etc/ssl/certs/ca-certificates.crt")
        self.assertRegex(str(ca.exception).lower(), r"certificate|root cert")
        address = socket.getaddrinfo(
            os.environ["PGHOST"], 5432, type=socket.SOCK_STREAM
        )[0][4][0]
        with self.assertRaises(psycopg.OperationalError) as hostname:
            connection(host="wrong-hostname.invalid", hostaddr=address)
        self.assertRegex(
            str(hostname.exception).lower(),
            r"does not match host name|hostname|host name.*certificate",
        )
        print(
            "verify-full wrong CA and wrong hostname reached certificate-specific failures",
            flush=True,
        )

    def test_10_stable_ties_literal_filter_and_bounded_pages(self):
        vector = stored(self.ids[0])[2]
        fixture_ids = [uuid4() for _ in range(13)]
        with connection(owner=True) as owner:
            for i, note_id in enumerate(fixture_ids):
                owner.execute(
                    "INSERT INTO semantic_notes.notes(id,title,body,embedding) VALUES(%s,%s,'Paging fixture reuses a real model vector',%s)",
                    (note_id, "Literal %_" if i < 2 else f"Paging {i}", vector),
                )
        try:
            first = self.client.get("/api/notes").json()
            second = self.client.get("/api/notes?page=2").json()
            self.assertEqual(len(first["notes"]), 12)
            self.assertEqual(len(second["notes"]), 4)
            self.assertFalse(
                set(n["id"] for n in first["notes"])
                & set(n["id"] for n in second["notes"])
            )
            result = self.client.post(
                "/api/search", json={"q": "reading", "k": 10, "title_filter": "%_"}
            ).json()["results"]
            self.assertEqual(
                [n["id"] for n in result], sorted(str(i) for i in fixture_ids[:2])
            )
            self.assertEqual(result[0]["distance"], result[1]["distance"])
            self.assertLessEqual(
                len(
                    self.client.post(
                        "/api/search", json={"q": "reading", "k": 3}
                    ).json()["results"]
                ),
                3,
            )
        finally:
            with connection(owner=True) as owner:
                owner.execute(
                    "DELETE FROM semantic_notes.notes WHERE id = ANY(%s)",
                    (fixture_ids,),
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
