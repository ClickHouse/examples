import os
import pathlib
import subprocess
import time
import urllib.request


def launch(log):
    names = ['HOME', 'PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD',
             'PGSSLROOTCERT', 'APP_SECRET', 'MEMBER_001_TOKEN', 'MEMBER_002_TOKEN']
    runtime = {key: os.environ[key] for key in names}
    runtime['PHP_CLI_SERVER_WORKERS'] = '4'
    # CLI server is a local test runner, not a production process manager.
    process = subprocess.Popen(['php', '-d', 'post_max_size=8K', '-S', '127.0.0.1:8080',
                               '-t', 'public', 'public/index.php'], env=runtime,
                               stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError('Runtime exited during startup')
        try:
            with urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=0.2) as response:
                if response.status == 200:
                    return process
        except OSError:
            time.sleep(0.1)
    os.killpg(process.pid, 15)
    raise RuntimeError('Runtime readiness deadline exceeded')


if __name__ == '__main__':
    folder = pathlib.Path(os.environ['EVIDENCE_DIR'])
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / 'server.log').open('w') as log:
        process = launch(log)
    (folder / 'server.pid').write_text(str(process.pid))
    print('Native runtime group PID', process.pid, '; four forked HTTP workers plus parent; runtime-only environment.')
