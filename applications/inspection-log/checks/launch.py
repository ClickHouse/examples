#!/usr/bin/env python3
"""Start the loopback runtime with only its required environment.

Use KEY=value lines (no shell syntax) in the private runtime file. Setup
credentials inherited by this helper are excluded from the Puma process.
"""
import os
from pathlib import Path
import sys

ALLOWED = {'PGHOST', 'PGPORT', 'PGDATABASE', 'PGSSLROOTCERT', 'PGPASSWORD', 'SESSION_SECRET', 'TZ'}
values = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line or line.startswith('#'):
        continue
    key, value = line.split('=', 1)
    if key in ALLOWED:
        if key in values:
            raise SystemExit('Duplicate runtime setting')
        values[key] = value
for key in ('PGHOST', 'PGSSLROOTCERT', 'PGPASSWORD', 'SESSION_SECRET'):
    if not values.get(key):
        raise SystemExit('Missing runtime setting: ' + key)
env = {key: os.environ[key] for key in ('PATH', 'HOME', 'LANG') if key in os.environ}
env.update(values)
os.chdir(Path(__file__).resolve().parents[1])
os.execvpe('bundle', ['bundle', 'exec', 'puma', '-C', 'puma.rb'], env)
