import json
import os
import re
import sys
from pathlib import Path
import requests

state_file = Path('.deployment/persistence.json')
base = 'http://127.0.0.1:3000'
session = requests.Session()

def token(response):
    return re.search(r'name="csrf-token" content="([^"]+)"', response.text).group(1)

if sys.argv[1] == 'before':
    page = session.get(base + '/session/new', timeout=20)
    response = session.post(base + '/session', data={'email': 'alex@example.test',
        'password': os.environ['DEMO_PASSWORD'], 'authenticity_token': token(page)},
        allow_redirects=False, timeout=20)
    assert response.status_code == 303
    page = session.get(base + '/tickets/new', timeout=20)
    response = session.post(base + '/tickets', data={'ticket[subject]': 'Persistence: connection help',
        'body': 'This exact initial message must survive a server process restart.',
        'authenticity_token': token(page)}, allow_redirects=False, timeout=20)
    assert response.status_code == 303
    state_file.write_text(json.dumps({'cookies': session.cookies.get_dict(),
        'url': response.headers['Location']}))
    state_file.chmod(0o600)
    print('Before restart: authenticated customer cookie and durable ticket/reply recorded.')
else:
    state = json.loads(state_file.read_text())
    for name, value in state['cookies'].items():
        session.cookies.set(name, value, domain='127.0.0.1', path='/')
    response = session.get(state['url'], allow_redirects=False, timeout=20)
    assert response.status_code == 200
    assert 'Persistence: connection help' in response.text
    assert response.text.count('This exact initial message must survive a server process restart.') == 1
    assert 'Alex' in response.text
    state_file.unlink()
    print('After actual process restart: same encrypted cookie authenticates; exact ticket/reply persist once.')
