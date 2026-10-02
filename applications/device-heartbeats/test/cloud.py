"""Destructive acceptance against your own dedicated Cloud fixture; standard-library tools only."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

EXECUTABLE = os.environ['HEARTBEATS_EXECUTABLE']
OUTPUT = Path(os.environ.get('EVIDENCE_DIR', '.'))
OUTPUT.mkdir(parents=True, exist_ok=True)
RUNTIME_FIELDS = ['PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD',
                  'PGSSLROOTCERT', 'NORTH_TOKEN', 'SOUTH_TOKEN', 'PORT']
RUNTIME = {field: os.environ[field] for field in RUNTIME_FIELDS}
server = None
server_log = None


def database(sql, role='owner', check=True):
    env = dict(os.environ, PGSSLMODE='verify-full')
    if role == 'owner':
        env.update(PGUSER='heartbeats_migration', PGPASSWORD=os.environ['MIGRATION_PASSWORD'])
    elif role == 'admin':
        env.update(PGUSER=os.environ['ADMIN_USER'], PGPASSWORD=os.environ['ADMIN_PASSWORD'])
    elif role != 'runtime':
        raise ValueError('unknown role')
    result = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                            input=sql, text=True, capture_output=True, env=env, timeout=20)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result


def call(device=None, body=None, path=None, south=False, raw=None, media='application/json', auth=True):
    target = path or f'/devices/{device}/samples'
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    headers = {'Content-Type': media}
    if auth:
        headers['Authorization'] = 'Bearer ' + RUNTIME['SOUTH_TOKEN' if south else 'NORTH_TOKEN']
    request = urllib.request.Request('http://127.0.0.1:' + RUNTIME['PORT'] + target,
                                     data=data, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=12)
    except urllib.error.HTTPError as error:
        response = error
    text = response.read()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        value = {}
    return response.status, value


def payload(sequence='1', reading=12, sample=None, observed=None):
    value = {'sample_id': sample or str(uuid.uuid4()), 'sequence': sequence, 'reading': reading}
    if observed is not None:
        value['observed_at'] = observed
    return value


def device(name, project='north'):
    assert re.fullmatch(r'[a-z][a-z0-9-]{0,31}', name) and project in ('north', 'south')
    database(f"INSERT INTO heartbeats.devices(project,id) VALUES('{project}','{name}')")
    return name


def state(name):
    return json.loads(database(f"""SELECT json_build_object('latest',latest_sequence::text,'count',sample_count,
        'rows',(SELECT count(*) FROM heartbeats.samples WHERE project='north' AND device='{name}'))
        FROM heartbeats.devices WHERE project='north' AND id='{name}'""").stdout)


def start():
    global server, server_log
    server_log = open(OUTPUT / f'server-{time.time_ns()}.log', 'w')
    server = subprocess.Popen([EXECUTABLE], env=RUNTIME, stdout=server_log, stderr=subprocess.STDOUT)
    for _ in range(100):
        if server.poll() is not None:
            raise RuntimeError('runtime startup failed; inspect private server log')
        try:
            if call(path='/health', auth=False)[0] == 200:
                return
        except OSError:
            pass
        time.sleep(.1)
    raise RuntimeError('runtime did not become ready')


def stop():
    if server is not None and server.poll() is None:
        server.send_signal(signal.SIGTERM)
        assert server.wait(timeout=15) == 0
    if server_log is not None:
        server_log.close()


def held_pair(name, first, second):
    # An independent administrator psql process holds the parent row. Runtime requests
    # use separate C++ pool connections; pg_blocking_pids proves actual database waits.
    env = dict(os.environ, PGUSER=os.environ['ADMIN_USER'], PGPASSWORD=os.environ['ADMIN_PASSWORD'],
               PGSSLMODE='verify-full')
    holder = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    holder.stdin.write(f"BEGIN; SELECT id FROM heartbeats.devices WHERE project='north' AND id='{name}' FOR UPDATE;\n")
    holder.stdin.flush()
    assert holder.stdout.readline().strip() == name
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        a = executor.submit(call, name, first)
        b = executor.submit(call, name, second)
        try:
            for _ in range(60):
                rows = database("""SELECT pg_stat_clear_snapshot();
                    SELECT count(*) FROM pg_stat_activity WHERE application_name='device-heartbeats'
                    AND cardinality(pg_blocking_pids(pid))>0""", role='admin').stdout.splitlines()
                if rows and rows[-1] == '2':
                    break
                time.sleep(.02)
            else:
                raise AssertionError('two runtime database sessions were not observed blocked')
        finally:
            holder.stdin.write('COMMIT;\n'); holder.stdin.flush(); holder.stdin.close()
            assert holder.wait(timeout=10) == 0
        return a.result(timeout=12), b.result(timeout=12)


def scoped_and_input():
    name = device('scope-case')
    original = payload('9007199254740993', -12, observed='2026-10-02T12:13:14Z')
    status, created = call(name, original)
    assert status == 201 and created['sample']['sequence'] == original['sequence']
    assert created['sample']['observed_at'] == original['observed_at']
    assert created['sample']['received_at'] != original['observed_at']
    upper = dict(original, sample_id=original['sample_id'].upper())
    assert call(name, upper) == (200, dict(created, replay=True))
    assert call(name, dict(original, reading=-11))[0] == 409
    assert call(name, original, south=True)[0] == 404
    assert call(name, south=True)[1]['rows'] == []
    foreign = device('foreign-only', 'south')
    assert call(foreign, payload())[0] == 404
    assert call(name, dict(payload(), project='south'))[0] == 400
    for reading in [True, 1.0, 1.5, 1000001, -1000001, None]:
        assert call(name, payload(reading=reading))[0] == 400
    for sequence in ['0', '01', '-1', '9223372036854775808', '9' * 1000, 1, True]:
        assert call(name, payload(sequence))[0] == 400
    for observed in ['2025-02-29T00:00:00Z', '2026-10-02T24:00:00Z', '2026-10-02T12:00:00+00:00', '\ud800']:
        assert call(name, payload(observed=observed))[0] == 400
    assert call(name, payload(sample='\ud800'))[0] == 400
    assert call(name, raw=b'{bad')[0] == 400
    assert call(name, raw=b'{"sample_id":"a","sequence":"1","reading":1,}')[0] == 400
    assert call(name, raw=b'{}' + b' ' * 5000)[0] == 413
    assert call(name, payload(), auth=False)[0] == 401
    assert call(name, payload(), media='application/jsonp')[0] == 415
    assert call(name, payload(), media='application/jsonjunk')[0] == 415
    assert call(name, payload('9223372036854775807'), media='Application/JSON; charset=utf-8')[0] == 201
    assert call(path='/devices?limit=101')[0] == 400
    assert call(path=f'/devices/{name}/samples?before=9223372036854775808')[0] == 400
    assert state(name) == {'latest': '9223372036854775807', 'count': 2, 'rows': 2}


def concurrent_replay():
    name = device('replay-case')
    original = payload('10')
    a, b = held_pair(name, original, original)
    assert sorted([a[0], b[0]]) == [200, 201]
    assert a[1]['sample'] == b[1]['sample']
    assert state(name) == {'latest': '10', 'count': 1, 'rows': 1}
    assert call(name, payload('9'))[0] == 409
    assert call(name, original)[0] == 200


def competing_sequence():
    name = device('sequence-case')
    a, b = held_pair(name, payload('42', 1), payload('42', 2))
    assert sorted([a[0], b[0]]) == [201, 409]
    assert state(name) == {'latest': '42', 'count': 1, 'rows': 1}
    assert call(name, payload('41'))[0] == 409
    assert call(name, payload('43'))[0] == 201


def rollback_and_release():
    name = device('rollback-case')
    database("""CREATE FUNCTION heartbeats.reject_latest() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
        IF NEW.id='rollback-case' THEN RAISE EXCEPTION 'acceptance latest failure'; END IF; RETURN NEW; END $$;
        CREATE TRIGGER acceptance_latest BEFORE UPDATE ON heartbeats.devices
        FOR EACH ROW EXECUTE FUNCTION heartbeats.reject_latest();""")
    try:
        for number in range(10):
            assert call(name, payload(str(number + 1)))[0] == 503
        assert state(name) == {'latest': '0', 'count': 0, 'rows': 0}
    finally:
        database('DROP TRIGGER acceptance_latest ON heartbeats.devices; DROP FUNCTION heartbeats.reject_latest()')
    assert call(name, payload())[0] == 201  # More errors than admission slots; no retained cycle/capacity leak.
    assert state(name) == {'latest': '1', 'count': 1, 'rows': 1}


def deferred_commit():
    name = device('commit-case')
    original = payload()
    database("""CREATE FUNCTION heartbeats.reject_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
        IF NEW.device='commit-case' THEN RAISE EXCEPTION 'acceptance deferred commit failure'; END IF; RETURN NEW; END $$;
        CREATE CONSTRAINT TRIGGER acceptance_commit AFTER INSERT ON heartbeats.samples
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION heartbeats.reject_commit();""")
    try:
        assert call(name, original)[0] == 503  # Final SQL succeeded, actual COMMIT failed; never201.
        assert state(name) == {'latest': '0', 'count': 0, 'rows': 0}
    finally:
        database('DROP TRIGGER acceptance_commit ON heartbeats.samples; DROP FUNCTION heartbeats.reject_commit()')
    assert call(name, original)[0] == 201
    assert call(name, original)[0] == 200


def cap_and_history():
    name = device('cap-case')
    database("""INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading)
        SELECT 'north','cap-case',('60000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,n,n
        FROM generate_series(1,200) AS g(n);
        UPDATE heartbeats.devices SET latest_sequence=200,sample_count=200 WHERE project='north' AND id='cap-case';""")
    saved = payload('1', 1, '60000000-0000-4000-8000-000000000001')
    assert call(name, saved)[0] == 200
    assert call(name, payload('201'))[1]['error'] == 'history_full'
    seen = []
    before = None
    for _ in range(5):
        path = f'/devices/{name}/samples?limit=100' + (f'&before={before}' if before else '')
        status, value = call(path=path)
        assert status == 200 and len(value['rows']) <= 100
        if not value['rows']:
            break
        seen.extend(row['id'] for row in value['rows'])
        before = value['next_before']
    assert len(seen) == len(set(seen)) == 200
    assert seen == sorted(seen, key=int, reverse=True)
    assert state(name) == {'latest': '200', 'count': 200, 'rows': 200}


def permissions():
    for statement in ["UPDATE heartbeats.samples SET reading=1", "DELETE FROM heartbeats.samples",
                      "UPDATE heartbeats.devices SET id='x'", 'CREATE TABLE heartbeats.forbidden(id int)',
                      'CREATE SCHEMA forbidden', 'CREATE TEMP TABLE forbidden(id int)',
                      'SELECT * FROM heartbeats.schema_versions']:
        result = database(statement, role='runtime', check=False)
        assert result.returncode and '42501' in result.stderr
    for statement, code in [
        ("UPDATE heartbeats.devices SET latest_sequence=-1", '23514'),
        ("UPDATE heartbeats.devices SET sample_count=201", '23514'),
        ("INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading) VALUES('north','foreign-only','70000000-0000-4000-8000-000000000001',1,1)", '23503'),
        ("INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading) VALUES('north','meter-a','70000000-0000-4000-8000-000000000002',0,1)", '23514')]:
        result = database(statement, role='runtime', check=False)
        assert result.returncode and code in result.stderr
    first = database("INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading) VALUES('north','meter-a','70000000-0000-4000-8000-000000000003',1,1)", role='runtime')
    assert first.returncode == 0
    duplicate = database("INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading) VALUES('north','meter-a','70000000-0000-4000-8000-000000000003',2,1)", role='runtime', check=False)
    assert duplicate.returncode and '23505' in duplicate.stderr and 'retained_sample' in duplicate.stderr
    # This direct trusted-role fixture deliberately does not update parent metadata.


def tls():
    def probe(env, filename):
        result = subprocess.run([EXECUTABLE, '--check-db'], env=env, capture_output=True, text=True, timeout=15)
        (OUTPUT / filename).write_text(result.stdout + result.stderr)
        return result
    wrong_ca = probe(dict(RUNTIME, PGSSLROOTCERT=os.environ['WRONG_CA']), 'tls-wrong-ca.log')
    assert wrong_ca.returncode and re.search(r'certificate verify failed', wrong_ca.stdout + wrong_ca.stderr, re.I)
    address = socket.gethostbyname(RUNTIME['PGHOST'])
    wrong_host = probe(dict(RUNTIME, PGHOST=address), 'tls-wrong-host.log')
    assert wrong_host.returncode and re.search(r'does not match host name', wrong_host.stdout + wrong_host.stderr, re.I)
    positive = probe(RUNTIME, 'tls-positive.log')
    assert positive.returncode == 0 and 'Verified database connection' in positive.stdout


def restart():
    name = device('restart-case')
    original = payload('123', 55)
    status, saved = call(name, original)
    assert status == 201
    before = state(name)
    old_pid = server.pid
    stop()  # wait/exact exit0 BEFORE starting replacement
    start()
    assert server.pid != old_pid
    assert call(name, original) == (200, dict(saved, replay=True)) and state(name) == before


if __name__ == '__main__':
    print('Actual PostgreSQL:', database('SHOW server_version').stdout.strip())
    start()
    try:
        cases = [scoped_and_input, concurrent_replay, competing_sequence, rollback_and_release,
                 deferred_commit, cap_and_history, permissions, tls, restart]
        for case in cases:
            case()
            print('PASS', case.__name__, flush=True)
        print(f'All {len(cases)} Cloud cases passed', flush=True)
    finally:
        stop()
