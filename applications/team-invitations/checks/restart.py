#!/usr/bin/env python3
"""Real process restart with explicit runtime-only child environments."""
import json
import os
import subprocess
import time
from pathlib import Path
from cloud import http, acceptance

fixture = json.loads(Path(os.environ['TEST_RESTART_FIXTURE']).read_text())
evidence = Path(os.environ['TEST_EVIDENCE_DIR'])
evidence.mkdir(parents=True, exist_ok=True)
keys = ['PATH', 'HOME', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGSSLROOTCERT', 'USER_TOKENS', 'PORT']
child_env = {key: os.environ[key] for key in keys if key in os.environ}
for key in ['PGHOST', 'PGUSER', 'PGPASSWORD', 'PGSSLROOTCERT', 'USER_TOKENS']:
    assert child_env.get(key), f'Missing runtime field{key}'
assert child_env['PGUSER'] == 'invites_app'


def start(number):
    log = (evidence / f'restart-api-{number}.txt').open('w')
    process = subprocess.Popen(['.build/debug/Invitations', 'serve', '--env', 'production'], env=child_env,
                               stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            assert process.poll() is None, 'Runtime child failed during readiness'
            try:
                if http('GET', '/memberships', None)[0] == 401:
                    break
            except OSError:
                pass
            time.sleep(.1)
        else:
            raise AssertionError('Runtime readiness deadline exceeded')
        environment = Path(f'/proc/{process.pid}/environ').read_bytes()
        for name in [b'INVITES_ADMIN_PASSWORD=', b'INVITES_MIGRATOR_PASSWORD=', b'TEST_MIGRATOR_PASSWORD=']:
            assert name not in environment, 'Child inherited a setup credential'
        assert acceptance(fixture['id'], fixture['secret'], fixture['actor']) == (200, fixture['membership'])
        return process, log
    except BaseException:
        process.terminate()
        process.wait(timeout=5)
        log.close()
        raise


def stop(process, log):
    process.terminate()
    process.wait(timeout=5)
    log.close()
    assert not Path(f'/proc/{process.pid}').exists(), 'First PID must be gone before replacement starts'


first, first_log = start(1)
first_pid = first.pid
stop(first, first_log)
second, second_log = start(2)
try:
    assert second.pid != first_pid
    print(f'External process restart:{first_pid}→{second.pid}; first gone before second launch; both runtime-only; consumed replay200 original membership', flush=True)
finally:
    stop(second, second_log)
