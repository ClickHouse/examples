"""Owned synthetic Cloud fixture only; start the runtime in a separate shell."""
import concurrent.futures
import datetime
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = os.environ.get('APP_BASE_URL', 'http://127.0.0.1:8080')
ROOMS = ['00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102']
MEMBERS = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002']


def request(path, values=None, token=None, raw=None):
    body = raw if raw is not None else (None if values is None else json.dumps(values).encode())
    headers = {'Content-Type': 'application/json'}
    if token is not None:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(BASE + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def sql(statement, expected=None):
    environment = {key: value for key, value in os.environ.items() if key != 'PGOPTIONS'}
    process = subprocess.run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c', statement],
                             env=environment, text=True, capture_output=True, timeout=12)
    if expected:
        assert process.returncode != 0 and expected in process.stderr, process.stderr
    else:
        assert process.returncode == 0, process.stderr
    return process.stdout.strip()


def booking(start, end, room=ROOMS[0], title='Synthetic booking'):
    return {'roomId': room, 'title': title, 'startAt': start, 'endAt': end}


def row(identity):
    return json.loads(sql("SELECT json_build_object('start',start_at,'end',end_at,'status',status,'revision',revision) "
                          f"FROM calendar.reservations WHERE id='{identity}'"))


def parallel(operations):
    barrier = threading.Barrier(len(operations))
    def run(operation):
        barrier.wait()
        return operation()
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(operations)) as executor:
        return list(executor.map(run, operations))


def main():
    first, second = os.environ['MEMBER_001_TOKEN'], os.environ['MEMBER_002_TOKEN']
    assert request('/rooms')[0] == 401
    assert request('/rooms', token='0' * 64)[0] == 401
    assert request('/rooms', token=first)[0] == 200
    overlapping = booking('2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z')
    outcomes = parallel([lambda: request('/reservations', overlapping, first),
                         lambda: request('/reservations', overlapping, second)])
    assert sorted(outcome[0] for outcome in outcomes) == [201, 409], outcomes
    winner = next(outcome[1] for outcome in outcomes if outcome[0] == 201)
    owner = first if outcomes[0][0] == 201 else second
    foreign = second if owner == first else first
    assert winner['startAt'] == '2026-11-01T08:00:00Z'
    print('Independent simultaneous HTTP workers: overlapping creates 201/409; one active interval.')
    status, adjacent = request('/reservations', booking('2026-11-01T09:00:00Z', '2026-11-01T10:00:00Z'), owner)
    assert status == 201, (status, adjacent)
    assert request('/reservations', booking('2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z', ROOMS[1]), owner)[0] == 201
    assert request('/reservations', booking('2026-11-01T09:00:00+01:00', '2026-11-01T10:00:00+01:00'), foreign)[0] == 409
    print('Adjacent intervals and different rooms accepted; equal instants with different offsets conflict.')
    before = row(winner['id'])
    status, _ = request('/reservations/' + winner['id'] + '/reschedule',
                        {'expectedRevision': 1, 'startAt': '2026-11-01T09:30:00Z', 'endAt': '2026-11-01T10:30:00Z'}, owner)
    assert status == 409 and row(winner['id']) == before
    assert request('/reservations/' + winner['id'] + '/reschedule',
                   {'expectedRevision': 1, 'startAt': '2026-11-01T07:00:00Z', 'endAt': '2026-11-01T08:00:00Z'}, owner)[0] == 200
    moved = row(winner['id'])
    assert moved['revision'] == 2
    assert request('/reservations/' + winner['id'] + '/cancel', {'expectedRevision': 1}, owner)[0] == 409
    assert request('/reservations/' + winner['id'] + '/cancel', {'expectedRevision': 2}, foreign)[0] == 404
    print('Reschedule conflict preserved original interval/revision; valid next request succeeds; stale409/foreign404.')

    # Hold the owner's row longer than the foreign request's bound. The filtered
    # locking query must not acquire this row or wait behind its lock.
    holder = subprocess.Popen(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    holder.stdin.write(f"BEGIN; SELECT id FROM calendar.reservations WHERE id='{winner['id']}' FOR UPDATE;\n")
    holder.stdin.flush()
    for _ in range(4):
        line = holder.stdout.readline()
        assert line, 'Lock holder exited before readiness'
        if winner['id'] in line:
            break
    else:
        raise AssertionError('Lock holder did not return the owned row')
    try:
        began = time.monotonic()
        assert request('/reservations/' + winner['id'] + '/cancel', {'expectedRevision': 2}, foreign)[0] == 404
        elapsed = time.monotonic() - began
        assert holder.poll() is None, 'Lock holder ended before foreign response'
        print('Foreign edit while actual owned row is locked:404 in', round(elapsed, 3), 's; no foreign row lock acquired.')
    finally:
        holder.stdin.write('ROLLBACK;\n\\q\n'); holder.stdin.flush()
        holder.communicate(timeout=5)

    for invalid in [booking('infinity', '2026-11-01T09:00:00Z'),
                    booking('2026-11-01T08:00:00', '2026-11-01T09:00:00Z'),
                    booking('2026-11-01T08:00:00Z', '2026-11-01T08:00:00Z'),
                    booking('2026-11-01T09:00:00Z', '2026-11-01T08:00:00Z'),
                    {**overlapping, 'roomId': None}, {**overlapping, 'title': None},
                    {**overlapping, 'memberId': MEMBERS[1]}, {**overlapping, 'title': 'NUL\0title'}]:
        assert request('/reservations', invalid, first)[0] == 400
    assert request('/reservations/' + winner['id'] + '/cancel', {'expectedRevision': None}, owner)[0] == 400
    assert request('/reservations', token=first, raw=b'{"title":"' + b'x' * 4097)[0] == 413
    assert request('/reservations', token=first, raw=b'{"title":"\xed\xa0\x80"}')[0] == 400
    query = urllib.parse.urlencode({'roomId': ROOMS[0], 'from': '2026-11-01T00:00:00Z', 'to': '2026-11-02T00:00:00Z'})
    status, listed = request('/reservations?' + query, token=first)
    assert status == 200 and not listed['hasMore'] and len(listed['reservations']) == 2
    assert all('memberId' not in value for value in listed['reservations'])
    print('Authentication/input/body/window controls passed; explicit public DTOs omit ownership/token internals.')

    cancellation, creation = parallel([
        lambda: request('/reservations/' + winner['id'] + '/cancel', {'expectedRevision': 2}, owner),
        lambda: request('/reservations', booking('2026-11-01T07:00:00Z', '2026-11-01T08:00:00Z'), foreign)])
    assert cancellation[0] == 200 and creation[0] in (201, 409), (cancellation, creation)
    assert row(winner['id'])['status'] == 'cancelled'
    replay = request('/reservations/' + winner['id'].upper() + '/cancel', {'expectedRevision': 2}, owner)
    assert replay[0] == 200 and replay[1] == cancellation[1]
    if creation[0] == 409:
        assert request('/reservations', booking('2026-11-01T07:00:00Z', '2026-11-01T08:00:00Z'), foreign)[0] == 201
    assert sql("SELECT count(*) FROM calendar.reservations a JOIN calendar.reservations b ON a.id<b.id AND a.room_id=b.room_id AND a.status='active' AND b.status='active' AND tstzrange(a.start_at,a.end_at,'[)') && tstzrange(b.start_at,b.end_at,'[)')") == '0'
    print('Cancel/create race:', cancellation[0], creation[0], '; cancellation frees range; matching uppercase-path replay stable; no active overlaps.')

    values = f"'{uuid.uuid4()}','{ROOMS[0]}','{MEMBERS[0]}','Direct constraint','2026-11-10T08:00:00Z','2026-11-10T09:00:00Z','active',1"
    def direct_race():
        return subprocess.run(['psql','-X','-At','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-c',
            'BEGIN; INSERT INTO calendar.reservations VALUES (' + values.replace(values.split(',')[0], "'" + str(uuid.uuid4()) + "'", 1) + '); SELECT pg_sleep(0.4); COMMIT;'],
            text=True, capture_output=True, timeout=8)
    results = parallel([direct_race, direct_race])
    assert sorted(result.returncode for result in results) == [0, 1]
    assert any('23P01' in result.stderr for result in results)
    print('Direct independent database transactions, no API locks: one commit/one23P01 under overlapping insert.')
    for start, end in [('infinity','infinity'),('2026-11-12T09:00:00Z','2026-11-12T08:00:00Z'),
                       ('2026-11-12T08:00:00Z','2026-11-12T08:00:00Z'),('2026-11-12T08:00:00Z','2026-11-13T08:00:00Z')]:
        sql(f"INSERT INTO calendar.reservations VALUES ('{uuid.uuid4()}','{ROOMS[0]}','{MEMBERS[0]}','Invalid direct','{start}','{end}','active',1)", '23514')
    for statement in ['CREATE TABLE calendar.denied(id int)', 'DELETE FROM calendar.reservations',
                      "UPDATE calendar.reservations SET member_id='" + MEMBERS[1] + "'"]:
        process = subprocess.run(['psql','-X','-At','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-c',statement],
            env={**os.environ,'PGUSER':'calendar_app','PGPASSWORD':os.environ['CALENDAR_APP_PASSWORD']},
            text=True,capture_output=True,timeout=8)
        assert process.returncode and '42501' in process.stderr
    print('Direct finite/order/duration checks23514 and runtime DDL/delete/ownership-change grants42501.')
    sql("INSERT INTO calendar.reservations SELECT gen_random_uuid(),'" + ROOMS[1] + "','" + MEMBERS[0] +
        "','Bounded-list fixture','2026-12-01T00:00:00Z'::timestamptz+n*interval '1 hour'," +
        "'2026-12-01T00:00:00Z'::timestamptz+n*interval '1 hour'+interval '30 minutes','active',1 " +
        "FROM generate_series(0,100) AS n")
    try:
        query = urllib.parse.urlencode({'roomId': ROOMS[1], 'from': '2026-12-01T00:00:00Z', 'to': '2026-12-31T00:00:00Z'})
        status, bounded = request('/reservations?' + query, token=first)
        assert status == 200 and len(bounded['reservations']) == 100 and bounded['hasMore']
        keys = [(value['startAt'], value['id']) for value in bounded['reservations']]
        assert keys == sorted(keys) and len(set(keys)) == 100
        invalid = urllib.parse.urlencode({'roomId': ROOMS[1], 'from': '2026-12-01T00:00:00Z', 'to': '2027-01-02T00:00:00Z'})
        assert request('/reservations?' + invalid, token=first)[0] == 400
    finally:
        sql("DELETE FROM calendar.reservations WHERE title='Bounded-list fixture'")
    print('Actual101-row availability fixture returns100 ordered DTOs/hasMore;32-day window400. All Cloud controls passed.')


if __name__ == '__main__':
    main()
