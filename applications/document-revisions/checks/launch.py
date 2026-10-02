#!/usr/bin/env python3
"""Start the production jar with only runtime configuration and ordinary OS variables."""
import os
from pathlib import Path
allowed = ("PATH", "HOME", "LANG", "JDBC_URL", "PGUSER", "PGPASSWORD", "PGSSLROOTCERT",
           "ACCOUNT_001_TOKEN", "ACCOUNT_002_TOKEN", "QUARKUS_HTTP_PORT")
jar = Path(__file__).resolve().parents[1] / "target/quarkus-app/quarkus-run.jar"
os.execvpe("java", ["java", "-jar", str(jar)], {k: os.environ[k] for k in allowed if k in os.environ})
