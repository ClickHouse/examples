import base64
import hashlib
import hmac
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "tokens", Path(__file__).parents[1] / "scripts/tokens.py"
)
tokens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tokens)


class FixtureIssuerTests(unittest.TestCase):
    def test_signed_scoped_short_lived_token(self):
        secret = "a" * 128
        value = tokens.issue(secret, "checklist_north", 60, now=1790960000)
        head, body, signature = value.split(".")
        decoded = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        self.assertEqual(
            decoded,
            {
                "role": "checklist_north",
                "aud": "checklist-runs",
                "iat": 1790960000,
                "exp": 1790960060,
            },
        )
        expected = hmac.new(
            secret.encode(), (head + "." + body).encode(), hashlib.sha256
        ).digest()
        self.assertEqual(tokens.b64url(expected), signature)

    def test_unknown_role_cannot_be_issued(self):
        with self.assertRaises(ValueError):
            tokens.issue("a" * 128, "checklist_owner")

    def test_short_secret_rejected(self):
        with self.assertRaises(ValueError):
            tokens.issue("too-short", "checklist_south")

    def test_lifetime_bounds(self):
        for seconds in (0, 901, True):
            with self.assertRaises(ValueError):
                tokens.issue("a" * 128, "checklist_south", seconds)


if __name__ == "__main__":
    unittest.main()
