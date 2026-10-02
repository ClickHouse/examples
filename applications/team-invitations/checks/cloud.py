#!/usr/bin/env python3
"""Explicit live acceptance suite. Run only against this example's dedicated fixture."""
import concurrent.futures
import hashlib
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = os.environ.get('TEST_BASE_URL', 'http://127.0.0.1:3000')
TOKENS = json.loads(os.environ['USER_TOKENS'])
USERS = [f'00000000-0000-4000-8000-{i:012d}' for i in range(1, 5)]
TEAMS = ['a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001']


def http(method, path, actor=0, data=None, raw=None):
    body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
    headers = {'Content-Type': 'application/json'}
    if actor is not None:
        headers['Authorization'] = 'Bearer ' + TOKENS[USERS[actor]]
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or '{}')


def database(statement, runtime=False, expect=None):
    env = dict(os.environ)
    env.update(PGSSLMODE='verify-full')
    if not runtime:
        env.update(PGUSER='invites_migrator', PGPASSWORD=os.environ['TEST_MIGRATOR_PASSWORD'], PGOPTIONS='-c role=invites_owner -c timezone=UTC')
    process = subprocess.run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c', statement],
                             env=env, text=True, capture_output=True, timeout=25)
    if expect:
        assert process.returncode != 0 and expect in process.stderr, f'Expected database SQLSTATE {expect}'
        return expect
    assert process.returncode == 0, 'Dedicated fixture SQL failed'
    return process.stdout.strip()


def issued(team, recipient):
    status, body = http('POST', f'/teams/{TEAMS[team]}/invitations', team,
                        {'recipientUserId': USERS[recipient], 'ttlMinutes': 1})
    assert status == 201, f'Issue expected201, got{status}'
    identifier = body['invitation']['id']
    secret = body['secret']
    assert len(secret) == 43
    stored = database(f"SELECT token_digest FROM invites.invitations WHERE id='{identifier}'")
    assert stored == hashlib.sha256(secret.encode()).hexdigest() and stored != secret
    assert 'tokenDigest' not in body['invitation'] and 'secret' not in body['invitation']
    return identifier, secret


def acceptance(identifier, secret, actor):
    return http('POST', f'/invitations/{identifier}/accept', actor, {'secret': secret})


def datetime_from_iso(value):
    from datetime import datetime
    return datetime.fromisoformat(value)


def locked_expiry(expiry_id, expiry_secret):
    env = dict(os.environ, PGUSER='invites_migrator', PGPASSWORD=os.environ['TEST_MIGRATOR_PASSWORD'], PGSSLMODE='verify-full', PGOPTIONS='-c role=invites_owner -c timezone=UTC')
    # Set the short expiry AFTER the fixture connection acquired the lock.
    # Slow connection setup must not consume the pre-expiry observation window.
    locker = subprocess.Popen(['stdbuf', '-oL', 'psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], env=env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    locker.stdin.write(f"BEGIN; SELECT id FROM invites.invitations WHERE id='{expiry_id}' FOR UPDATE; UPDATE invites.invitations SET created_at=clock_timestamp()-interval '1 minute',expires_at=clock_timestamp()+interval '2 seconds' WHERE id='{expiry_id}';\n\\echo LOCKED\nSELECT json_build_object('pre_expiry',clock_timestamp()<expires_at,'expires_at',expires_at,'locked_at',clock_timestamp()) FROM invites.invitations WHERE id='{expiry_id}'; SELECT pg_sleep(3); COMMIT;\n")
    locker.stdin.close()
    while locker.stdout.readline().strip() != 'LOCKED':
        assert locker.poll() is None, 'Fixture lock not acquired'
    lock_fact = json.loads(locker.stdout.readline())
    assert (datetime_from_iso(lock_fact['expires_at']) - datetime_from_iso(lock_fact['locked_at'])).total_seconds() >= 1.9, 'Fixture connection must not consume expiry margin'
    assert lock_fact['pre_expiry'], 'HTTP must begin while invitation is still pending and unexpired'
    from datetime import datetime, timezone
    assert datetime.now(timezone.utc) < datetime.fromisoformat(lock_fact['expires_at']), 'Deadline elapsed before HTTP started'
    started = time.monotonic()
    status, _ = acceptance(expiry_id, expiry_secret, 3)
    elapsed = time.monotonic() - started
    assert locker.wait(timeout=5) == 0 and status == 410 and elapsed >= 2.0, f'Expiry wait{elapsed}, status{status}'
    assert database(f"SELECT status FROM invites.invitations WHERE id='{expiry_id}'") == 'pending'
    assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[1]}' AND user_id='{USERS[3]}'") == '0'
    print(f'Pre-expiry lock fact:{lock_fact}; independent row lock held3s across expiry; waiting acceptance410 after{elapsed:.3f}s, no membership passed', flush=True)



def main():
    assert database('SELECT count(*) FROM invites.memberships') == '0', 'Use a fresh seeded fixture'
    assert http('GET', '/memberships', None)[0] == 401
    assert http('POST', f'/teams/{TEAMS[0]}/invitations', 1, {'recipientUserId': USERS[2]})[0] == 404
    assert http('POST', f'/teams/{TEAMS[0]}/invitations', 0, {'recipientUserId': USERS[2], 'adminId': USERS[0]})[0] == 400
    assert http('POST', f'/teams/{TEAMS[0]}/invitations', 0, {'recipientUserId': USERS[2], 'ttlMinutes': 0})[0] == 400
    assert http('POST', f'/teams/{TEAMS[0]}/invitations', 0, raw=b'{bad')[0] == 400
    assert http('POST', f'/teams/{TEAMS[0]}/invitations', 0, raw=b' ' * 5000)[0] == 413
    assert http('GET', '/memberships?limit=51', 2)[0] == 400
    assert http('GET', '/memberships?after=invalid', 2)[0] == 400
    print('Auth, forged owner, strict input,4KiB payload and list bounds passed', flush=True)

    identifier, secret = issued(0, 2)
    assert acceptance(identifier, secret, 3)[0] == 404
    assert acceptance(identifier, 'A' * 43, 2)[0] == 404
    assert http('POST', f'/invitations/{identifier}/revoke', 1, {})[0] == 404
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        responses = list(executor.map(lambda _: acceptance(identifier, secret, 2), range(8)))
    statuses = [status for status, _ in responses]
    assert statuses.count(201) == 1 and statuses.count(200) == 7, f'Unexpected competing accepts {statuses}'
    member = responses[0][1]
    assert all(body == member for _, body in responses)
    assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[0]}' AND user_id='{USERS[2]}'") == '1'
    database(f"UPDATE invites.invitations SET created_at=clock_timestamp()-interval '2 minutes',expires_at=clock_timestamp()-interval '1 minute' WHERE id='{identifier}'")
    assert acceptance(identifier, secret, 2) == (200, member)
    assert acceptance(identifier, 'A' * 43, 2)[0] == 404
    assert http('POST', f'/invitations/{identifier}/revoke', 0, {})[0] == 409
    database(f"INSERT INTO invites.memberships(id,team_id,user_id,created_at) VALUES(gen_random_uuid(),'{TEAMS[0]}','{USERS[2]}',clock_timestamp())", expect='23505')
    print(f'Eight simultaneous accepts:{statuses}; one membership, matching expired replay and independent unique23505 passed', flush=True)

    rollback_id, rollback_secret = issued(1, 2)
    database("CREATE FUNCTION invites.force_membership_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced failure' USING ERRCODE='P0001'; END $$; CREATE TRIGGER force_membership_failure BEFORE INSERT ON invites.memberships FOR EACH ROW EXECUTE FUNCTION invites.force_membership_failure()")
    try:
        assert acceptance(rollback_id, rollback_secret, 2)[0] == 503
        assert database(f"SELECT status||':'||(accepted_membership_id IS NULL)::text FROM invites.invitations WHERE id='{rollback_id}'") == 'pending:true'
        assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[1]}' AND user_id='{USERS[2]}'") == '0'
    finally:
        database('DROP TRIGGER force_membership_failure ON invites.memberships; DROP FUNCTION invites.force_membership_failure()')
    assert acceptance(rollback_id, rollback_secret, 2)[0] == 201
    print('Forced failure after accepted-state update rolled back invitation and membership; retry201 passed', flush=True)

    race_id, race_secret = issued(0, 3)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        accept_future = executor.submit(acceptance, race_id, race_secret, 3)
        revoke_future = executor.submit(http, 'POST', f'/invitations/{race_id}/revoke', 0, {})
        a, r = accept_future.result()[0], revoke_future.result()[0]
    assert (a, r) in [(201, 409), (409, 200)], f'Unexpected accept/revoke outcomes{a,r}'
    state = database(f"SELECT status FROM invites.invitations WHERE id='{race_id}'")
    assert state == ('accepted' if a == 201 else 'revoked')
    assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[0]}' AND user_id='{USERS[3]}'") == ('1' if a == 201 else '0')
    print(f'Actual accept/revoke race:{a}/{r}, final{state}; one terminal outcome passed', flush=True)

    expiry_id, expiry_secret = issued(1, 3)
    locked_expiry(expiry_id, expiry_secret)

    retained_id, retained_secret = issued(0, 1)
    retained_status, retained_member = acceptance(retained_id, retained_secret, 1)
    assert retained_status == 201
    fixture = Path(os.environ['TEST_RESTART_FIXTURE'])
    fixture.write_text(json.dumps({'id': retained_id, 'secret': retained_secret, 'actor': 1, 'membership': retained_member}))
    fixture.chmod(0o600)
    wrong_member = database(f"SELECT id FROM invites.memberships WHERE team_id='{TEAMS[1]}' AND user_id='{USERS[2]}'")
    database(f"BEGIN; UPDATE invites.invitations SET accepted_membership_id='{wrong_member}' WHERE id='{retained_id}'; COMMIT", expect='23503')
    print('Deferred composite accepted-membership FK rejects other team/recipient23503 passed', flush=True)
    assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[0]}' AND user_id='{USERS[1]}'") == '1'
    for statement in ["CREATE TABLE invites.forbidden(id int)", 'DELETE FROM invites.memberships',
                      "UPDATE invites.invitations SET token_digest=repeat('0',64)",
                      'UPDATE invites.invitations SET expires_at=clock_timestamp()',
                      'UPDATE invites.teams SET admin_id=admin_id', "INSERT INTO invites.users VALUES(gen_random_uuid(),'forbidden')"]:
        database(statement, runtime=True, expect='42501')
    database("UPDATE invites.invitations SET status='broken'", runtime=True, expect='23514')
    print('Runtime role:DDL/delete/digest/expiry/admin/user writes42501; invalid state23514 passed', flush=True)
    status, page = http('GET', f'/teams/{TEAMS[0]}/invitations?limit=1', 0)
    assert status == 200 and len(page['items']) == 1 and page.get('nextAfter')
    _, next_page = http('GET', f"/teams/{TEAMS[0]}/invitations?limit=1&after={page['nextAfter']}", 0)
    assert len(next_page['items']) == 1 and next_page['items'][0]['id'] != page['items'][0]['id']
    assert http('GET', f'/teams/{TEAMS[0]}/invitations', 1)[0] == 404
    _, members = http('GET', '/memberships', 2)
    assert len(members['items']) == 2 and all(item['userID'].lower() == USERS[2] for item in members['items'])
    assert all('secret' not in item and 'tokenDigest' not in item for item in page['items'])
    print('Scoped keyset list, explicit DTOs and membership scope passed; live suite complete', flush=True)


if __name__ == '__main__':
    main()
