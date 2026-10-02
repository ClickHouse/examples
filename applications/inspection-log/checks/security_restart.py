#!/usr/bin/env python3
"""Real adapter TLS/permissions and actual Puma exit/restart on the owned fixture.

VM-only helper: RUNTIME_ENV, SERVER_PID_FILE and EVIDENCE_DIR are required.
Administrator PG* may be inherited for test work; launch.py strips them before
exec. This does not install packages or alter the database fixture.
"""
import csv
import html
import io
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import http.cookiejar

APP = Path(__file__).resolve().parents[1]
OUT = Path(os.environ['EVIDENCE_DIR'])
RUNTIME = Path(os.environ['RUNTIME_ENV'])
PID_FILE = Path(os.environ['SERVER_PID_FILE'])
settings = dict(line.split('=', 1) for line in RUNTIME.read_text().splitlines() if line and not line.startswith('#'))
positive = dict(os.environ, **settings)

# The same Database.connect path used by config.ru configures libpq verify-full.
probe = "require './lib/database'; db=InspectionLog::Database.connect; p db.fetch('SELECT current_user').first; db.disconnect"
command = ['bundle', 'exec', 'ruby', '-e', probe]
result = subprocess.run(command, cwd=APP, env=positive, capture_output=True, text=True, timeout=15)
assert result.returncode == 0, result.stderr.replace(settings['PGHOST'], '[private endpoint]')
print('Actual Sequel Database.connect same-endpoint positive: inspection_app, verify-full')
for label, overrides, expected in [
    ('untrusted system CA', {'PGSSLROOTCERT':'/etc/ssl/certs/ca-certificates.crt'}, 'certificate verify failed'),
    ('hostname mismatch', {'PGHOST':socket.getaddrinfo(settings['PGHOST'], 5432, socket.AF_INET)[0][4][0]}, 'does not match host name'),
]:
    env = dict(positive, **overrides)
    result = subprocess.run(command, cwd=APP, env=env, capture_output=True, text=True, timeout=15)
    diagnostic = result.stderr
    assert result.returncode != 0 and expected in diagnostic, diagnostic.replace(settings['PGHOST'], '[private endpoint]')
    assert 'PG::ConnectionBad' in diagnostic
    # Preserve precise failure class/message, excluding private endpoint/IP.
    for value in (settings['PGHOST'], overrides.get('PGHOST', '')):
        if value:
            diagnostic = diagnostic.replace(value, '[private endpoint]')
    (OUT / ('tls-' + label.replace(' ', '-') + '.txt')).write_text(diagnostic)
    print(f'Actual Sequel TLS negative: {label}: PG::ConnectionBad / {expected}')

BASE = 'http://127.0.0.1:9292'
def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as response:
        assert response.status == 200
        return response.read().decode()

def content(body):
    # Persisted content, excluding layout changes and freshly generated CSRF state.
    return (html.unescape(re.search(r'<h1>(.*?)</h1>', body, re.S).group(1)),
            html.unescape(re.search(r'<p class="note">(.*?)</p>', body, re.S).group(1)),
            html.unescape(re.search(r'<p class="hint">Saved (.*?)</p>', body, re.S).group(1)),
            re.search(r'\d{4}-\d{2}-\d{2}', body).group())

query = urllib.parse.urlencode({'asset_id':1, 'from':'2026-01-01', 'to':'2026-01-01', 'outcome':''})
before_content = content(get('/inspections/1'))
before_csv = get('/report.csv?' + query)
assert list(csv.DictReader(io.StringIO(before_csv)))[0]['inspected_on'] == '2026-01-01'
first_pid = int(PID_FILE.read_text())
os.kill(first_pid, signal.SIGTERM)
for _ in range(100):
    try:
        os.kill(first_pid, 0)
    except ProcessLookupError:
        break
    time.sleep(.1)
else:
    raise AssertionError('Original Puma did not exit; replacement will not start')
assert not Path(f'/proc/{first_pid}').exists()
with (OUT / 'server-restarted.log').open('w') as log:
    process = subprocess.Popen([sys_executable := '/usr/bin/python3', str(APP/'checks/launch.py'), str(RUNTIME)],
                               cwd=APP, env=os.environ, stdout=log, stderr=log, start_new_session=True)
PID_FILE.write_text(str(process.pid) + '\n')
for _ in range(100):
    assert process.poll() is None, 'Replacement exited'
    try:
        get('/')
        break
    except Exception:
        time.sleep(.1)
else:
    raise AssertionError('Replacement not ready')
assert process.pid != first_pid
assert content(get('/inspections/1')) == before_content
assert get('/report.csv?' + query) == before_csv
runtime_names = {part.split(b'=', 1)[0].decode() for part in Path(f'/proc/{process.pid}/environ').read_bytes().split(b'\0') if part}
assert not runtime_names & {'APP_PASSWORD','MIGRATOR_PASSWORD','PGUSER','CLICKHOUSE_API_KEY','CLICKHOUSE_API_SECRET'}
assert runtime_names <= {'PATH','HOME','LANG','PGHOST','PGPORT','PGDATABASE','PGSSLROOTCERT','PGPASSWORD','SESSION_SECRET','TZ'}
print(f'Actual Puma process {first_pid} exited before {process.pid} started; saved asset/note/day/time/request and exact CSV persisted')
print('Replacement runtime environment names: ' + ', '.join(sorted(runtime_names)))

# A new cookie/CSRF session can replay the browser's original retained request.
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()), NoRedirect())
with client.open(BASE + '/') as response:
    body = response.read().decode()
token = html.unescape(re.search(r'name="authenticity_token" value="([^"]*)"', body).group(1))
request_id = re.search(r'Retained request ID: ([0-9a-f-]+)', before_content[2]).group(1)
fields = dict(authenticity_token=token, request_id=request_id.upper(), asset_id='1', inspected_on='2026-01-01',
              outcome='watch', housing='ok', cable='issue', label='ok', note=before_content[1])
request = urllib.request.Request(BASE+'/inspections', data=urllib.parse.urlencode(fields).encode(),
                                headers={'Content-Type':'application/x-www-form-urlencoded', 'Origin':BASE})
try:
    response = client.open(request)
except urllib.error.HTTPError as error:
    response = error
with response:
    assert response.status == 303 and response.headers['Location'].endswith('/inspections/1')
assert get('/report.csv?' + query) == before_csv
print('Retained exact form replay (uppercase UUID) after actual process restart returned original inspection1 at full cap')
(OUT/'restart.json').write_text(json.dumps({'original_pid':first_pid,'replacement_pid':process.pid,'original_gone':True,
                                          'content_equal':True,'csv_equal':True,'retained_replay':303}, indent=2)+'\n')
