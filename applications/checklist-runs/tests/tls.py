"""Exercise libpq verification in the actual PostgREST application process."""

import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[1]
BINARY = os.environ.get("POSTGREST_BIN", str(APP / ".local/bin/postgrest"))
RUNTIME_KEYS = (
    "PGHOST",
    "PGPORT",
    "PGDATABASE",
    "PGUSER",
    "PGPASSWORD",
    "PGSSLMODE",
    "PGSSLROOTCERT",
    "PGCONNECT_TIMEOUT",
    "PGRST_JWT_SECRET",
)


def environment():
    return {
        "HOME": os.environ["HOME"],
        "PATH": "/usr/bin:/bin",
        "LANG": "C.UTF-8",
        **{key: os.environ[key] for key in RUNTIME_KEYS},
    }


class NativeTLS(unittest.TestCase):
    def assert_connection_fails(self, changes, expected_fragments):
        with tempfile.TemporaryFile() as output:
            child = subprocess.Popen(
                [BINARY, "postgrest.conf"],
                cwd=APP,
                env={**environment(), "PGRST_SERVER_PORT": "3001", **changes},
                stdout=output,
                stderr=output,
            )
            try:
                code = child.wait(timeout=25)
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.wait(timeout=5)
            output.seek(0)
            message = output.read().decode(errors="replace").lower()
        self.assertNotEqual(code, 0)
        self.assertTrue(
            any(fragment in message for fragment in expected_fragments),
            "The native failure did not identify the intended TLS verification control.",
        )
        print(
            "Actual PostgREST process failed for the expected certificate/name reason; exit",
            code,
        )

    def test_untrusted_ca(self):
        self.assert_connection_fails(
            {"PGSSLROOTCERT": "/etc/ssl/certs/ca-certificates.crt"},
            ("certificate verify failed", "unable to get local issuer certificate"),
        )

    def test_wrong_hostname_same_actual_server(self):
        actual_ip = socket.getaddrinfo(
            os.environ["PGHOST"], 5432, type=socket.SOCK_STREAM
        )[0][4][0]
        self.assert_connection_fails(
            {"PGHOST": "wrong-hostname.invalid", "PGHOSTADDR": actual_ip},
            ("does not match host name", "does not match hostname"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
