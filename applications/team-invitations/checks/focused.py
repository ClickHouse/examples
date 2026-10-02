#!/usr/bin/env python3
"""Focused followups after cloud.py on the same dedicated fixture."""
import concurrent.futures
from cloud import issued, acceptance, database, locked_expiry, TEAMS, USERS

first_id, first_secret = issued(1, 0)
second_id, second_secret = issued(1, 0)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    first = executor.submit(acceptance, first_id, first_secret, 0)
    second = executor.submit(acceptance, second_id, second_secret, 0)
    statuses = [first.result()[0], second.result()[0]]
assert sorted(statuses) == [201, 409], f'Distinct invitation race{statuses}'
assert database(f"SELECT count(*) FROM invites.memberships WHERE team_id='{TEAMS[1]}' AND user_id='{USERS[0]}'") == '1'
assert database(f"SELECT string_agg(status,',' ORDER BY status) FROM invites.invitations WHERE id IN ('{first_id}','{second_id}')") == 'accepted,pending'
print(f'Distinct invitations race:{statuses}; one membership, loser stays pending passed', flush=True)
expiry_id, expiry_secret = issued(1, 3)
locked_expiry(expiry_id, expiry_secret)
print('Focused contention/expiry followups complete', flush=True)
