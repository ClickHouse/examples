"""Destructive acceptance on your own dedicated Cloud fixture. Never follows redirects."""
import concurrent.futures
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

EXECUTABLE = os.environ['REDIRECTS_EXECUTABLE']
OUTPUT = Path(os.environ.get('EVIDENCE_DIR', '.'))
OUTPUT.mkdir(parents=True, exist_ok=True)
RUNTIME_FIELDS = ['PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD',
                  'PGSSLROOTCERT', 'NORTH_TOKEN', 'SOUTH_TOKEN', 'PORT']
RUNTIME = {key: os.environ[key] for key in RUNTIME_FIELDS}
server = None
server_log = None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None


opener = urllib.request.build_opener(NoRedirect)


def call(path, body=None, south=False, method=None, raw=None, auth=True, media='application/json'):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    headers = {'Content-Type': media}
    if auth:
        headers['Authorization'] = 'Bearer ' + RUNTIME['SOUTH_TOKEN' if south else 'NORTH_TOKEN']
    request = urllib.request.Request('http://127.0.0.1:' + RUNTIME['PORT'] + path,
                                     data=data, headers=headers, method=method)
    try:
        response = opener.open(request, timeout=12)
    except urllib.error.HTTPError as error:
        response = error
    text = response.read()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        value = {}
    return response.status, {name.lower(): value for name, value in response.headers.items()}, value


def database(sql, role='owner', check=True):
    env = dict(os.environ, PGSSLMODE='verify-full')
    if role == 'owner':
        env.update(PGUSER='redirects_migration', PGPASSWORD=os.environ['MIGRATION_PASSWORD'])
    elif role == 'admin':
        env.update(PGUSER=os.environ['ADMIN_USER'], PGPASSWORD=os.environ['ADMIN_PASSWORD'])
    elif role != 'runtime':
        raise ValueError('unknown control role')
    result = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                            input=sql, text=True, capture_output=True, env=env, timeout=20)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result


def create(slug, destination='https://example.invalid/guide', south=False, expiry=None):
    body = {'slug': slug, 'destination': destination}
    if expiry is not None:
        body['expires_at'] = expiry
    return call('/links', body, south=south)


def start():
    global server, server_log
    server_log = open(OUTPUT / f'server-{time.time_ns()}.log', 'w')
    server = subprocess.Popen([EXECUTABLE], env=RUNTIME, stdout=server_log, stderr=subprocess.STDOUT)
    for _ in range(100):
        if server.poll() is not None:
            raise RuntimeError('runtime startup failed; inspect private log')
        try:
            if call('/health', auth=False)[0] == 200:
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


def warm_pool():
    # Cold TLS connection establishment is not part of the short held-lock barrier.
    # Warm the real runtime pool with bounded reads; retain production timeouts.
    for _ in range(6):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            responses = list(executor.map(lambda _: call('/links'), range(4)))
        assert all(response[0] in (200, 503) for response in responses)
        count = int(database("SELECT count(*) FROM pg_stat_activity WHERE application_name='redirect-links'", role='admin').stdout)
        if count == 4:
            assert call('/links')[0] == 200
            print('Warm real runtime pool: four sessions')
            return
    raise AssertionError('four runtime pool sessions did not become ready')


def held_pair(first, second):
    warm_pool()
    env = dict(os.environ, PGUSER=os.environ['ADMIN_USER'], PGPASSWORD=os.environ['ADMIN_PASSWORD'],
               PGSSLMODE='verify-full')
    holder = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    holder.stdin.write("BEGIN; SELECT id FROM redirect_links.accounts WHERE id='north' FOR UPDATE;\n")
    holder.stdin.flush()
    assert holder.stdout.readline().strip() == 'north'
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        a = executor.submit(create, first)
        b = executor.submit(create, second)
        try:
            for _ in range(60):
                rows = database("""SELECT pg_stat_clear_snapshot();
                    SELECT count(*) FROM pg_stat_activity WHERE application_name='redirect-links'
                    AND cardinality(pg_blocking_pids(pid))>0""", role='admin').stdout.splitlines()
                if rows and rows[-1] == '2':
                    break
                time.sleep(.01)
            else:
                raise AssertionError('two actual Diesel HTTP sessions not observed blocked')
            assert call('/health', auth=False)[0] == 200
            assert call('/links')[0] == 200
            assert holder.poll() is None and not a.done() and not b.done()
            print('Two actual blocked writers; health and bounded DB read finish before lock release')
        finally:
            holder.stdin.write('COMMIT;\n')
            holder.stdin.flush()
            holder.stdin.close()
            assert holder.wait(timeout=10) == 0
        return a.result(timeout=12), b.result(timeout=12)


def canonical_and_scope():
    status, _, saved = create('My-Guide', 'HTTPS://EXAMPLE.COM:443/a')
    assert status == 201 and saved['slug'] == 'my-guide' and saved['destination'] == 'https://example.com/a'
    for method in ['GET', 'HEAD']:
        status, headers, body = call('/r/MY-GUIDE', auth=False, method=method)
        assert status == 307 and headers['location'] == saved['destination']
        assert headers['cache-control'] == 'no-store' and body == {}
    assert create('my-GUIDE', saved['destination'])[0] == 409
    assert call('/links', south=True)[2]['rows'] == []
    assert call('/links/my-guide/disable', {'revision': '1'}, south=True)[0] == 404
    assert call('/links', {'slug': 'forged-owner', 'destination': 'https://example.com', 'owner': 'south'})[0] == 400
    for slug in ['ab', '-abc', 'abc-', 'abc/def', 'a\x00b', 'ＡＢＣ', 'health', 'a' * 41]:
        assert create(slug)[0] == 400
    for url in ['file:///tmp/a', 'https://user@example.com', 'https://@example.com', 'https:example.com',
                'https://example.com/\n', 'https://example.com/\u0085', ' https://example.com', 'https://example.com/' + 'a' * 2048]:
        assert create('bad-url', url)[0] == 400
    assert call('/links', raw=br'{"slug":"\ud800","destination":"https://example.com"}')[0] == 400
    assert call('/links', raw=b'{"slug":"abc","slug":"def","destination":"https://example.com"}')[0] == 400
    assert call('/links', raw=b'{' + b' ' * 5000 + b'}')[0] == 413
    assert call('/links', {'slug': 'abc', 'destination': 'https://example.com'}, media='application/jsonp')[0] == 400
    assert call('/links', auth=False)[0] == 401
    for query in ['limit=21', 'before=0', 'before=9223372036854775808', 'owner=south']:
        assert call('/links?' + query)[0] == 400
    for path in ['/r/unknown', '/r/ab', '/r/%FF', '/r/']:
        status, headers, _ = call(path, auth=False)
        assert status == 404 and headers['cache-control'] == 'no-store'


def concurrent_collision():
    first, second = held_pair('Same-Slug', 'same-slug')
    print('Contending HTTP statuses:', first[0], second[0])
    assert sorted([first[0], second[0]]) == [201, 409]
    assert database("SELECT count(*) FROM redirect_links.links WHERE slug='same-slug'").stdout.strip() == '1'
    assert database("SELECT link_count=(SELECT count(*) FROM redirect_links.links WHERE account='north') FROM redirect_links.accounts WHERE id='north'").stdout.strip() == 't'


def cap_contention():
    count = int(database("SELECT count(*) FROM redirect_links.links WHERE account='north'").stdout)
    database(f"""BEGIN;
        INSERT INTO redirect_links.links(account,slug,destination)
        SELECT 'north','cap-fill-'||n,'https://example.invalid/cap' FROM generate_series(1,{19-count}) n;
        UPDATE redirect_links.accounts SET link_count=19 WHERE id='north'; COMMIT;""")
    first, second = held_pair('cap-final-a', 'cap-final-b')
    print('Contending HTTP statuses:', first[0], second[0])
    assert sorted([first[0], second[0]]) == [201, 409]
    assert database("SELECT link_count FROM redirect_links.accounts WHERE id='north'").stdout.strip() == '20'
    assert database("SELECT count(*) FROM redirect_links.links WHERE account='north'").stdout.strip() == '20'
    database("""BEGIN; DELETE FROM redirect_links.links WHERE account='north' AND slug LIKE 'cap-%';
        UPDATE redirect_links.accounts SET link_count=(SELECT count(*) FROM redirect_links.links WHERE account='north') WHERE id='north'; COMMIT;""")


def second_write_rollback():
    before = database("SELECT link_count FROM redirect_links.accounts WHERE id='north'").stdout
    database("""CREATE FUNCTION redirect_links.reject_insert() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.slug='rollback-check' THEN RAISE EXCEPTION 'fixture insert failure'; END IF; RETURN NEW; END $$;
        CREATE TRIGGER reject_insert BEFORE INSERT ON redirect_links.links FOR EACH ROW EXECUTE FUNCTION redirect_links.reject_insert();""")
    try:
        assert create('rollback-check')[0] == 503
        assert database("SELECT link_count FROM redirect_links.accounts WHERE id='north'").stdout == before
        assert database("SELECT count(*) FROM redirect_links.links WHERE slug='rollback-check'").stdout.strip() == '0'
    finally:
        database('DROP TRIGGER reject_insert ON redirect_links.links; DROP FUNCTION redirect_links.reject_insert();')
    assert create('rollback-check')[0] == 201


def deferred_commit():
    before = database("SELECT link_count FROM redirect_links.accounts WHERE id='north'").stdout
    database("""CREATE FUNCTION redirect_links.reject_commit() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.slug='commit-check' THEN RAISE EXCEPTION 'fixture deferred failure'; END IF; RETURN NEW; END $$;
        CREATE CONSTRAINT TRIGGER reject_commit AFTER INSERT ON redirect_links.links DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION redirect_links.reject_commit();""")
    try:
        assert create('commit-check')[0] == 503
        assert database("SELECT link_count FROM redirect_links.accounts WHERE id='north'").stdout == before
        assert database("SELECT count(*) FROM redirect_links.links WHERE slug='commit-check'").stdout.strip() == '0'
    finally:
        database('DROP TRIGGER reject_commit ON redirect_links.links; DROP FUNCTION redirect_links.reject_commit();')
    assert create('commit-check')[0] == 201


def numeric_pages_and_max_id():
    start_id = 98
    assert database(f'SELECT count(*) FROM redirect_links.links WHERE id BETWEEN {start_id} AND {start_id+11}').stdout.strip() == '0'
    # Owner-only sequence acceleration puts actual HTTP inserts across the 99/100 boundary.
    database(f'ALTER SEQUENCE redirect_links.links_id_seq RESTART WITH {start_id}')
    created = []
    for index in range(12):
        status, _, row = create(f'page-{index}')
        assert status == 201
        created.append(row['id'])
    assert created == [str(n) for n in range(start_id, start_id+12)]
    database("""BEGIN; INSERT INTO redirect_links.links(id,account,slug,destination) OVERRIDING SYSTEM VALUE
        VALUES(9223372036854775807,'north','max-id','https://example.invalid/max');
        UPDATE redirect_links.accounts SET link_count=link_count+1 WHERE id='north'; COMMIT;""")
    expected = database("SELECT id FROM redirect_links.links WHERE account='north' ORDER BY redirect_links.links.id DESC").stdout.splitlines()
    seen, before = [], ''
    for _ in range(12):
        status, _, page = call('/links?limit=2' + ('&before=' + before if before else ''))
        assert status == 200
        if not page['rows']:
            break
        seen.extend(row['id'] for row in page['rows'])
        before = page['next_before']
    assert seen == expected and len(set(seen)) == len(seen)
    assert seen[0] == '9223372036854775807' and set(created).issubset(seen)
    print('Actual numeric pages:', seen, '; first page includes INT64_MAX')


def expiry_and_disable():
    assert call('/links/my-guide/disable', {'revision': '9'})[0] == 409
    assert call('/links/my-guide/disable', {'revision': 1})[0] == 400
    status, _, disabled = call('/links/my-guide/disable', {'revision': '1'})
    assert status == 200 and disabled['revision'] == '2'
    for revision in ['1', '2']:
        assert call('/links/my-guide/disable', {'revision': revision})[2] == disabled
    assert call('/links/my-guide/disable', {'revision': '3'})[0] == 409
    for method in ['GET', 'HEAD']:
        status, headers, _ = call('/r/my-guide', auth=False, method=method)
        assert status == 404 and 'location' not in headers and headers['cache-control'] == 'no-store'
    assert create('expired-link', south=True, expiry='1970-01-01T00:00:00Z')[0] == 201
    assert call('/r/expired-link', auth=False)[0] == 404
    assert create('boundary-link', south=True, expiry='2050-01-01T00:00:00Z')[0] == 201
    assert call('/r/boundary-link', auth=False)[0] == 307
    database("UPDATE redirect_links.links SET expires_at=clock_timestamp() WHERE slug='boundary-link'")
    assert call('/r/boundary-link', auth=False)[0] == 404


def permissions():
    for statement in ["UPDATE redirect_links.links SET destination='https://example.com'", "UPDATE redirect_links.links SET account='south'",
                      "UPDATE redirect_links.links SET slug='other'", "DELETE FROM redirect_links.links", "UPDATE redirect_links.accounts SET id='other'",
                      'CREATE TABLE redirect_links.forbidden(id integer)', 'CREATE SCHEMA forbidden', 'CREATE TEMP TABLE forbidden(id integer)',
                      'SELECT * FROM redirect_links.schema_versions']:
        result = database(statement, role='runtime', check=False)
        assert result.returncode and '42501' in result.stderr
    for statement, code in [("INSERT INTO redirect_links.links(account,slug,destination) VALUES('north','Bad-Slug','https://example.com')", '23514'),
                            ("INSERT INTO redirect_links.links(account,slug,destination) VALUES('other','bad-fk','https://example.com')", '23503'),
                            ("INSERT INTO redirect_links.links(account,slug,destination) VALUES('south','my-guide','https://example.com')", '23505')]:
        result = database(statement, role='runtime', check=False)
        assert result.returncode and code in result.stderr
        if code == '23505':
            assert 'links_slug_unique' in result.stderr
    before = database("SELECT link_count FROM redirect_links.accounts WHERE id='south'").stdout
    database("INSERT INTO redirect_links.links(account,slug,destination) VALUES('south','direct-write','https://example.invalid/trusted')", role='runtime')
    assert database("SELECT link_count FROM redirect_links.accounts WHERE id='south'").stdout == before
    assert database("SELECT count(*) FROM redirect_links.links WHERE slug='direct-write'").stdout.strip() == '1'
    print('Trusted runtime direct SQL can bypass the application counter protocol')


def tls():
    def probe(name, overrides):
        result = subprocess.run([EXECUTABLE, '--check-db'], env=dict(RUNTIME, **overrides), text=True,
                                capture_output=True, timeout=12)
        (OUTPUT / name).write_text(result.stdout + result.stderr)
        return result
    wrong_ca = probe('tls-wrong-ca.log', {'PGSSLROOTCERT': os.environ['WRONG_CA']})
    assert wrong_ca.returncode and 'certificate verify failed' in wrong_ca.stderr
    address = socket.getaddrinfo(RUNTIME['PGHOST'], int(RUNTIME['PGPORT']), type=socket.SOCK_STREAM)[0][4][0]
    wrong_host = probe('tls-wrong-host.log', {'PGHOST': address})
    assert wrong_host.returncode and 'does not match host name' in wrong_host.stderr
    positive = probe('tls-positive.log', {})
    assert positive.returncode == 0 and 'Verified Diesel connection' in positive.stdout


def restart():
    status, _, saved = create('restart-link', south=True)
    assert status == 201
    old = server.pid
    stop()
    assert server.poll() == 0
    start()
    assert server.pid != old
    rows = call('/links', south=True)[2]['rows']
    assert next(row for row in rows if row['slug'] == 'restart-link') == saved
    status, headers, _ = call('/r/restart-link', auth=False)
    assert status == 307 and headers['location'] == saved['destination']
    assert create('restart-link', south=True)[0] == 409  # Creation has no retained request/replay key.


if __name__ == '__main__':
    print('Actual PostgreSQL:', database('SHOW server_version').stdout.strip())
    start()
    try:
        cases = [canonical_and_scope, concurrent_collision, cap_contention, second_write_rollback,
                 deferred_commit, numeric_pages_and_max_id, expiry_and_disable, permissions, tls, restart]
        for case in cases:
            case()
            print('PASS', case.__name__)
        print('All', len(cases), 'HTTP/Cloud cases passed')
    finally:
        stop()
