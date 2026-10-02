#!/usr/bin/env python3
"""Synthetic acceptance against the real loopback app and its owned Cloud fixture.

Run in the VM with administrator PG* and APP_PASSWORD exported. This helper
never resets a fixture: it expects the browser's single saved record first.
"""
import concurrent.futures
import csv
import html
import io
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import http.cookiejar
import uuid

BASE = 'http://127.0.0.1:9292'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

class Session:
    def __init__(self):
        self.client = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()), NoRedirect())
        status, _, body = self.get('/')
        assert status == 200
        self.fields = dict(re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"', body))
        self.fields = {key: html.unescape(value) for key, value in self.fields.items()}
        self.fields.update(asset_id='1', inspected_on='2026-01-01', outcome='pass',
                           housing='ok', cable='issue', label='ok', note='Synthetic operator note')

    def request(self, path, data=None, headers=None):
        req = urllib.request.Request(BASE + path, data=data, headers=headers or {})
        try:
            response = self.client.open(req, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, response.headers, response.read().decode('utf-8')

    def get(self, path):
        return self.request(path)

    def post(self, fields=None, raw=None, origin=BASE):
        headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Origin': origin}
        data = raw if raw is not None else urllib.parse.urlencode(fields or self.fields).encode()
        return self.request('/inspections', data, headers)


def sql(statement, runtime=False, expected=None):
    env = dict(os.environ)
    if runtime:
        env.update(PGUSER='inspection_app', PGPASSWORD=os.environ['APP_PASSWORD'])
    command = ['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-At']
    result = subprocess.run(command, input='\\set VERBOSITY verbose\n' + statement,
                            text=True, capture_output=True, env=env, timeout=25)
    if expected:
        assert result.returncode != 0 and expected in result.stderr, result.stderr
        print(f'Actual runtime SQL rejection: {expected}')
        return
    assert result.returncode == 0, result.stderr.replace(os.environ['PGHOST'], '[private endpoint]')
    return result.stdout.strip()


def owner(statement):
    return sql('SET ROLE inspection_owner;\n' + statement)


def counts():
    return sql("SELECT (SELECT used FROM inspection_api.fixture_budget),"
               "(SELECT count(*) FROM inspection_api.inspections),"
               "(SELECT count(*) FROM inspection_api.inspection_results);")


def preserved(body, fields):
    # Browser evidence checks selected controls; here verify the exact retained
    # request and note on each server-side error response.
    assert f'value="{html.escape(fields["request_id"], quote=True)}"' in body
    note = re.search(r'<textarea[^>]*>(.*?)</textarea>', body, re.S)
    assert note and html.unescape(note.group(1)) == fields['note']


def report(asset=1, outcome=''):
    query = urllib.parse.urlencode(dict(asset_id=asset, **{'from':'2026-01-01', 'to':'2026-01-02'}, outcome=outcome))
    return Session().get('/report.csv?' + query)


if '--reports-only' not in sys.argv:
    assert counts() == '1|1|3', 'Run this once after the browser creates the first record'
    original = sql('SELECT request_id FROM inspection_api.inspections WHERE id=1;')
    assert sql("SELECT inspected_on::text FROM inspection_api.inspections WHERE id=1;") == '2026-01-01'
    print('Browser fixture SQL DATE stayed exactly 2026-01-01 in non-UTC runtime')

    # Native middleware controls through the real Puma listener.
    s = Session()
    missing = dict(s.fields); missing.pop('authenticity_token')
    assert s.post(missing)[0] == 403
    assert Session().post(origin='https://foreign.invalid')[0] == 403
    assert Session().request('/', headers={'Host':'foreign.invalid'})[0] == 403
    s = Session()
    raw = urllib.parse.urlencode(s.fields).encode()
    assert s.post(raw=raw + b'&%6Eote=duplicate')[0] == 400
    assert s.post(raw=b'%ZZ=invalid')[0] == 400
    assert s.post(raw=b'note=' + b'x' * 32768)[0] == 413
    assert s.request('/inspections', b'{}', {'Content-Type':'application/json', 'Origin':BASE})[0] == 415
    assert s.post(raw=raw + b'&unknown=value')[0] == 422
    assert s.post(raw=raw + b'&')[0] == 303  # Standard empty separator ignored.
    invalid = dict(s.fields, request_id=str(uuid.uuid4()), inspected_on='1999-12-31', note='Fields remain here')
    status, _, body = s.post(invalid)
    assert status == 422; preserved(body, invalid)
    assert s.post(raw=raw.replace(b'Synthetic+operator+note', b'%FF'))[0] == 400
    print('Real HTTP: missing CSRF/foreign Origin/Host403, duplicate/malformed/UTF-8 form400, body413, type415, fields422; empty separator accepted')

    # Independent cookie/CSRF sessions submit the same UUID concurrently.
    a, b = Session(), Session()
    retained_id = str(uuid.uuid4())
    for client in (a, b):
        client.fields.update(request_id=retained_id, note='Concurrent retained form', outcome='watch')
    before = counts()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda client: client.post(), [a, b]))
    assert [item[0] for item in results] == [303, 303]
    locations = [item[1]['Location'] for item in results]
    assert locations[0] == locations[1]
    assert counts() == '|'.join(str(int(n)+delta) for n, delta in zip(before.split('|'), [1, 1, 3]))
    changed = dict(a.fields, note='Changed submitted text <kept>')
    status, _, body = a.post(changed)
    assert status == 409; preserved(body, changed)
    assert sql(f"SELECT count(*) FROM inspection_api.inspections WHERE request_id='{retained_id}'") == '1'
    print('Concurrent retained UUID: two303 responses, same original inspection, one header/three children/one budget debit; changed content409 with fields retained')

    # Owner-only fault proves that the earlier writes reached the database, then
    # forces failure on the second child. Remove the fault even if an assertion fails.
    owner("""
    CREATE FUNCTION inspection_api.fail_second_child() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.check_name='cable' THEN
        IF NOT EXISTS (SELECT 1 FROM inspection_api.inspections WHERE id=NEW.inspection_id)
           OR NOT EXISTS (SELECT 1 FROM inspection_api.inspection_results
                          WHERE inspection_id=NEW.inspection_id AND check_name='housing') THEN
          RAISE EXCEPTION 'Fault fixture did not observe earlier writes';
        END IF;
        RAISE EXCEPTION 'Synthetic second-child fault after header and housing';
      END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER fault_second_child BEFORE INSERT ON inspection_api.inspection_results
    FOR EACH ROW EXECUTE FUNCTION inspection_api.fail_second_child();
    """)
    c = Session(); c.fields.update(note='Retain this entire failed form', request_id=str(uuid.uuid4()))
    before = counts()
    try:
        status, _, body = c.post()
        assert status == 503; preserved(body, c.fields)
        assert counts() == before
        assert sql(f"SELECT count(*) FROM inspection_api.inspections WHERE request_id='{c.fields['request_id']}'") == '0'
    finally:
        owner('DROP TRIGGER fault_second_child ON inspection_api.inspection_results; DROP FUNCTION inspection_api.fail_second_child();')
    assert c.post()[0] == 303
    assert c.post()[0] == 303
    assert counts() == '|'.join(str(int(n)+delta) for n, delta in zip(before.split('|'), [1, 1, 3]))
    print('Actual second-child failure503 after header/first child: budget/header/children all rolled back; unchanged retained form retried once successfully')

    # Direct runtime SQL cannot alter history, schema, or seeded assets.
    for statement in [
        "UPDATE inspection_api.inspections SET note='changed' WHERE id=1;",
        'DELETE FROM inspection_api.inspections WHERE id=1;',
        "UPDATE inspection_api.inspection_results SET result='issue' WHERE inspection_id=1;",
        "UPDATE inspection_api.assets SET name='changed' WHERE id=1;",
        'CREATE TABLE inspection_api.forbidden(id integer);',
        'CREATE TEMP TABLE forbidden(id integer);',
        'SET ROLE inspection_owner;',
    ]:
        sql(statement, runtime=True, expected='42501')
    sql('UPDATE inspection_api.fixture_budget SET used=201 WHERE id=1;', runtime=True, expected='23514')
    sql("INSERT INTO inspection_api.inspections(id,request_id,digest,asset_id,inspected_on,outcome,note) "
        f"VALUES(201,'{uuid.uuid4()}','{'0'*64}',1,'2026-01-01','pass','');", runtime=True, expected='23514')
    sql("INSERT INTO inspection_api.inspections(id,request_id,digest,asset_id,inspected_on,outcome,note) "
        f"VALUES(199,'{original}','{'0'*64}',1,'2026-01-01','pass','');", runtime=True, expected='23505')

    # Deliberately fill a synthetic owned fixture to one slot below its cap.
    # This is an acceptance fixture, not an application/admin HTTP route.
    owner("""
    BEGIN;
    INSERT INTO inspection_api.inspections(id,request_id,digest,asset_id,inspected_on,outcome,note)
    SELECT n,gen_random_uuid(),repeat('0',64),2,DATE '2026-01-02',
           CASE WHEN n <= (SELECT used+100 FROM inspection_api.fixture_budget WHERE id=1) THEN 'watch' ELSE 'fail' END,
           'Synthetic cap fixture'
    FROM generate_series((SELECT used+1 FROM inspection_api.fixture_budget WHERE id=1),199) n;
    INSERT INTO inspection_api.inspection_results(inspection_id,check_name,result)
    SELECT i.id,c,'ok' FROM inspection_api.inspections i CROSS JOIN unnest(ARRAY['housing','cable','label']) c
    WHERE i.asset_id=2;
    UPDATE inspection_api.fixture_budget SET used=199 WHERE id=1;
    COMMIT;
    """)
    assert counts() == '199|199|597'
    x, y = Session(), Session()
    for client in (x, y):
        client.fields.update(asset_id='3', note='Last fixture slot')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda client: client.post(), [x, y]))
    assert sorted(item[0] for item in results) == [303, 409]
    assert counts() == '200|200|600'
    assert a.post()[0] == 303  # The replay lookup deliberately precedes capacity.
    assert counts() == '200|200|600'
    print('Actual last-slot contention303/409: hard200 cap,600 children, no partial loser; retained exact retry still succeeds at cap')

status, _, body = report(2)
assert status == 422 and 'More than 100 rows match' in body
status, headers, body = report(2, 'watch')
rows = list(csv.DictReader(io.StringIO(body)))
assert status == 200 and len(rows) == 100
ids = [int(row['inspection_id']) for row in rows]
assert ids == sorted(ids) and 9 in ids and 10 in ids
assert all(row['inspected_on'] == '2026-01-02' for row in rows)
assert headers['Content-Disposition'].startswith('attachment;')
query = urllib.parse.urlencode({'asset_id':2, 'from':'2026-01-01','to':'2026-01-02','outcome':''})
status, _, body = Session().get('/history?' + query)
links = [int(n) for n in re.findall(r'href="/inspections/(\d+)"', body)]
assert status == 200 and len(links) == 25 and links == list(range(199,174,-1))
print('CSV101+ rejected422; exact100-row CSV has numeric9→10 order and Date output; bounded history25 has numeric199→175 order')
print('Focused bounded report controls passed on the immutable200-record fixture')
