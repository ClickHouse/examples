import json
import os
import pathlib
import signal
import time
import urllib.parse
from cloud import request, ROOMS
from launch import launch

folder = pathlib.Path(os.environ['EVIDENCE_DIR'])
old = int((folder / 'server.pid').read_text())
query = urllib.parse.urlencode({'roomId': ROOMS[0], 'from': '2026-11-01T00:00:00Z', 'to': '2026-11-02T00:00:00Z'})
status, before = request('/reservations?' + query, token=os.environ['MEMBER_001_TOKEN'])
assert status == 200
os.killpg(old, signal.SIGTERM)
for _ in range(100):
    try:
        os.killpg(old, 0)
    except ProcessLookupError:
        break
    time.sleep(0.1)
else:
    raise AssertionError('Original server process group did not exit before restart')
with (folder / 'server-restarted.log').open('w') as log:
    process = launch(log)
(folder / 'server.pid').write_text(str(process.pid))
assert process.pid != old
status, after = request('/reservations?' + query, token=os.environ['MEMBER_001_TOKEN'])
assert status == 200 and after == before
print('Actual native server-group restart', old, '→', process.pid,
      '; original group gone; authenticated UTC availability identical; runtime-only children.')
