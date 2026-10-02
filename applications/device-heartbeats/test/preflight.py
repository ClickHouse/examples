"""Exercise the compiled listener and orderly exit without database credentials."""
import os
import signal
import subprocess
import sys
import time
import urllib.request

process = subprocess.Popen([sys.argv[1], '--preflight'], env=dict(os.environ, PORT='4100'))
try:
    for attempt in range(100):
        if process.poll() is not None:
            raise RuntimeError('preflight listener exited before readiness')
        try:
            with urllib.request.urlopen('http://127.0.0.1:4100/health', timeout=1) as response:
                assert response.status == 200
                assert response.read() == b'{"status":"up"}'
            break
        except OSError:
            time.sleep(.05)
    else:
        raise RuntimeError('preflight listener did not become ready')
    process.send_signal(signal.SIGTERM)
    assert process.wait(timeout=10) == 0
    print('PASS compiled loopback readiness and SIGTERM exit')
finally:
    if process.poll() is None:
        process.kill()
        process.wait(timeout=5)
