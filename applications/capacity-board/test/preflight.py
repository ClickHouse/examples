import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

exe = sys.argv[1]
env = {**os.environ, "APP_ORIGIN": "http://127.0.0.1:5000"}
child = subprocess.Popen([exe, "--preflight"], env=env, stdout=subprocess.DEVNULL)
try:
    for attempt in range(100):
        try:
            with urllib.request.urlopen("http://127.0.0.1:5000/health", timeout=1) as response:
                assert response.status == 200
                break
        except (OSError, urllib.error.URLError):
            time.sleep(0.1)
    else:
        raise AssertionError("compiled listener did not start")
    for headers in [{"Host": "evil.example"}, {"Origin": "https://evil.example"}]:
        request = urllib.request.Request("http://127.0.0.1:5000/health", headers=headers)
        try:
            urllib.request.urlopen(request, timeout=2)
            raise AssertionError("untrusted host/origin accepted")
        except urllib.error.HTTPError as error:
            assert error.code == 403
    child.send_signal(signal.SIGTERM)
    assert child.wait(timeout=15) == 0
    print("PASS compiled loopback listener, Host/Origin rejection and confirmed SIGTERM exit")
finally:
    if child.poll() is None:
        child.kill()
        child.wait(timeout=5)
