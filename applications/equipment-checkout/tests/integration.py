"""Destructive fixture tests: use only a dedicated, migrated example service."""
import concurrent.futures
import os
import re
import threading
import time
import unittest
import uuid
from datetime import timedelta

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
import django
django.setup()
import psycopg
import requests
from django.contrib.auth import get_user_model
from django.db import IntegrityError, connection, transaction
from django.utils import timezone
from board.models import Item, Loan

BASE = os.environ.get("TEST_BASE_URL", "http://127.0.0.1:8000")
PASSWORD = "FixturePass-" + uuid.uuid4().hex


def login(username):
    session = requests.Session()
    page = session.get(BASE + "/accounts/login/", timeout=15)
    token = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', page.text).group(1)
    result = session.post(BASE + "/accounts/login/", data={"username": username, "password": PASSWORD,
                          "csrfmiddlewaretoken": token}, timeout=15, allow_redirects=False)
    assert result.status_code == 302, result.status_code
    return session


def post(session, path, **extra):
    return session.post(BASE + path, data={"csrfmiddlewaretoken": session.cookies["csrftoken"], **extra},
                        headers={"HX-Request": "true"}, timeout=20, allow_redirects=False)


class Acceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.prefix = "test-" + uuid.uuid4().hex[:10]
        cls.users = [get_user_model().objects.create_user(cls.prefix + str(i), password=PASSWORD,
                     is_staff=(i == 2), is_superuser=(i == 2)) for i in range(3)]
        cls.sessions = [login(user.username) for user in cls.users]

    @classmethod
    def tearDownClass(cls):
        Loan.objects.filter(item__asset_tag__startswith=cls.prefix).delete()
        Item.objects.filter(asset_tag__startswith=cls.prefix).delete()
        for user in cls.users:
            user.delete()
        connection.close()

    def setUp(self):
        self.item = Item.objects.create(asset_tag=self.prefix + uuid.uuid4().hex[:8], name="Fixture camera")

    def borrow(self, who=0):
        return post(self.sessions[who], f"/items/{self.item.pk}/borrow/")

    def test_authentication_and_methods(self):
        self.assertEqual(requests.get(BASE + "/", allow_redirects=False, timeout=15).status_code, 302)
        self.assertEqual(self.sessions[0].get(BASE + f"/items/{self.item.pk}/borrow/", timeout=15).status_code, 405)

    def test_csrf_rejection(self):
        result = self.sessions[0].post(BASE + f"/items/{self.item.pk}/borrow/", timeout=15)
        self.assertEqual(result.status_code, 403)
        self.assertFalse(Loan.objects.filter(item=self.item).exists())

    def test_identity_is_server_owned(self):
        result = post(self.sessions[0], f"/items/{self.item.pk}/borrow/", borrower=self.users[1].pk)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(Loan.objects.get(item=self.item).borrower_id, self.users[0].pk)

    def test_concurrent_checkout(self):
        barrier = threading.Barrier(2)
        def checkout(who):
            barrier.wait()
            return self.borrow(who).status_code
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(checkout, [0, 1]))
        self.assertEqual(sorted(results), [200, 409])
        self.assertEqual(Loan.objects.filter(item=self.item, returned_at__isnull=True).count(), 1)

    def test_inventory_disable_serializes_with_checkout(self):
        # ItemAdmin uses this same lock inside its atomic save transaction.
        started = threading.Event()
        def checkout():
            started.set()
            return self.borrow().status_code
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            with transaction.atomic():
                item = Item.objects.select_for_update().get(pk=self.item.pk)
                future = pool.submit(checkout)
                self.assertTrue(started.wait(timeout=5))
                time.sleep(0.5)
                self.assertFalse(future.done(), "checkout should wait for inventory update")
                item.enabled = False
                item.save(update_fields=["enabled"])
            self.assertEqual(future.result(timeout=20), 409)
        self.assertFalse(Loan.objects.filter(item=self.item).exists())

    def test_database_constraint_without_application_lock(self):
        Loan.objects.create(item=self.item, borrower=self.users[0])
        with self.assertRaises(IntegrityError), transaction.atomic():
            Loan.objects.create(item=self.item, borrower=self.users[1])

    def test_return_constraint(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Loan.objects.create(item=self.item, borrower=self.users[0], returned_at=timezone.now() - timedelta(days=1))

    def test_owner_return_and_idempotence(self):
        self.assertEqual(self.borrow().status_code, 200)
        self.assertEqual(self.borrow().status_code, 200)
        loan = Loan.objects.get(item=self.item)
        path = f"/loans/{loan.pk}/return/"
        self.assertEqual(post(self.sessions[1], path).status_code, 404)
        loan.refresh_from_db()
        self.assertIsNone(loan.returned_at)
        self.assertEqual(post(self.sessions[0], path).status_code, 200)
        loan.refresh_from_db()
        returned = loan.returned_at
        self.assertEqual(post(self.sessions[0], path).status_code, 200)
        loan.refresh_from_db()
        self.assertEqual(loan.returned_at, returned)
        self.assertEqual(self.borrow(1).status_code, 200)
        self.assertEqual(Loan.objects.filter(item=self.item).count(), 2)

    def test_staff_return_and_private_listing(self):
        self.borrow()
        loan = Loan.objects.get(item=self.item)
        self.assertNotIn(f'data-loan="{loan.pk}"', self.sessions[1].get(BASE + "/", timeout=15).text)
        self.assertIn(f'data-loan="{loan.pk}"', self.sessions[2].get(BASE + "/", timeout=15).text)
        self.assertEqual(post(self.sessions[2], f"/loans/{loan.pk}/return/").status_code, 200)

    def test_disabled_and_missing_items(self):
        self.item.enabled = False
        self.item.save()
        self.assertEqual(self.borrow().status_code, 409)
        self.assertEqual(post(self.sessions[0], "/items/999999999/borrow/").status_code, 404)
        self.assertEqual(post(self.sessions[0], "/items/nope/borrow/").status_code, 404)

    def test_admin_authorization_and_validation(self):
        self.assertEqual(self.sessions[0].get(BASE + "/admin/board/item/add/", allow_redirects=False, timeout=15).status_code, 302)
        page = self.sessions[2].get(BASE + "/admin/board/item/add/", timeout=15)
        token = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', page.text).group(1)
        result = self.sessions[2].post(BASE + "/admin/board/item/add/", data={"csrfmiddlewaretoken": token,
              "asset_tag": "", "name": "", "_save": "Save"}, timeout=15)
        self.assertEqual(result.status_code, 200)
        self.assertIn("This field is required", result.text)
        result = self.sessions[2].post(BASE + "/admin/board/item/add/", data={"csrfmiddlewaretoken": token,
              "asset_tag": self.prefix + "admin", "name": "Staff-added kit", "enabled": "on", "_save": "Save"}, timeout=15, allow_redirects=False)
        self.assertEqual(result.status_code, 302)
        self.assertTrue(Item.objects.filter(asset_tag=self.prefix + "admin").exists())

    def test_runtime_role_cannot_change_schema(self):
        with self.assertRaises(django.db.ProgrammingError), transaction.atomic():
            with connection.cursor() as cur:
                cur.execute("CREATE TABLE equipment.must_not_exist (id integer)")
        with self.assertRaises(django.db.ProgrammingError), transaction.atomic():
            with connection.cursor() as cur:
                cur.execute("UPDATE django_migrations SET name = name")

    def test_tls_chain_and_hostname_verification(self):
        with connection.cursor() as cur:
            cur.execute("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")
            self.assertTrue(cur.fetchone()[0])
        params = dict(host=os.environ["PGHOST"], port=os.environ.get("PGPORT", "5432"),
                      dbname=os.environ.get("PGDATABASE", "postgres"), user=os.environ["PGUSER"],
                      password=os.environ["PGPASSWORD"], sslmode="verify-full", connect_timeout=10)
        with self.assertRaises(psycopg.OperationalError) as wrong_ca:
            psycopg.connect(**params, sslrootcert="/etc/ssl/certs/ca-certificates.crt")
        self.assertIn("certificate verify failed", str(wrong_ca.exception).lower())
        import socket
        params["hostaddr"] = socket.gethostbyname(params["host"])
        params["host"] = "wrong-hostname.example.invalid"
        with self.assertRaises(psycopg.OperationalError) as wrong_host:
            psycopg.connect(**params, sslrootcert=os.environ["PGSSLROOTCERT"])
        self.assertIn("does not match host name", str(wrong_host.exception).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
