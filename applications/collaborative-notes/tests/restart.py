"""Restart only a reviewed local fixture process, with a private runtime env file."""
import os
import shlex
import signal
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
evidence = Path(os.environ.get('EVIDENCE_DIR', '/tmp/collaborative-notes-evidence'))
evidence.mkdir(parents=True, exist_ok=True)
pid_file = Path(os.environ['SERVER_PID_FILE'])
runtime_env = Path(os.environ['RUNTIME_ENV_FILE'])
old = int(pid_file.read_text())
assert Path(f'/proc/{old}/cwd').resolve() == root
assert b'dist-server/server/main.js' in Path(f'/proc/{old}/cmdline').read_bytes()
os.kill(old, signal.SIGTERM)
for _ in range(250):
    if not Path(f'/proc/{old}').exists():
        break
    time.sleep(0.1)
else:
    raise RuntimeError('Original process did not exit before replacement')
env = {'HOME': os.environ['HOME'], 'PATH': os.environ['PATH'], 'LANG': 'C.UTF-8'}
allowed = {'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGSSLMODE', 'PGSSLROOTCERT', 'WORKSPACE_TOKEN'}
for line in runtime_env.read_text().splitlines():
    key, value = line.split('=', 1)
    if key not in allowed:
        raise RuntimeError(f'Unexpected runtime key: {key}')
    env[key] = shlex.split(value)[0]
with (evidence / 'replacement-server.log').open('ab') as log:
    replacement = subprocess.Popen(['node', 'dist-server/server/main.js'], cwd=root, env=env, stdout=log, stderr=log, start_new_session=True)
pid_file.write_text(str(replacement.pid))
time.sleep(2)
assert replacement.poll() is None
(evidence / 'restart-process.txt').write_text(f'Original {old} exited before replacement {replacement.pid}; runtime-only keys {sorted(env)}\n')
print((evidence / 'restart-process.txt').read_text(), end='')
