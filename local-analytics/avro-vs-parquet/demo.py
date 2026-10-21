#!/usr/bin/env python3
"""Generate Avro/Parquet locally and compare two-column and all-column reads."""
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from dataset import N, NAMES, STRUCT, GEN, QUERY_SETTINGS, EXPORT_SETTINGS

ROOT = Path(__file__).resolve().parent


def sql_string(value):
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    env = dict(os.environ, DO_NOT_TRACK='1')
    managed = json.loads(subprocess.check_output(
        ['clickhousectl', 'local', 'which', '--json'], env=env, text=True))
    base = [managed['binary_path'], 'local', *QUERY_SETTINGS]
    output_root = ROOT / 'demo-output'
    output_root.mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='run-', dir=output_root))

    def query(sql, **kwargs):
        return subprocess.run(base + ['--query', sql], env=env, check=True, **kwargs)

    def digest(sql):
        process = subprocess.Popen(base + ['--query', sql + ' FORMAT RowBinary'],
                                   env=env, stdout=subprocess.PIPE)
        value = hashlib.sha256()
        with process.stdout:
            for chunk in iter(lambda: process.stdout.read(1024 * 1024), b''):
                value.update(chunk)
        if process.wait():
            raise RuntimeError('ClickHouse output validation failed')
        return value.hexdigest()

    print(subprocess.check_output([managed['binary_path'], 'local', '--version'], text=True).strip())
    (output / 'generate.sql').write_text(GEN + ';\n')
    files = {}
    for fmt, settings in EXPORT_SETTINGS.items():
        path = output / f'events.{fmt.lower()}'
        with path.open('xb') as stream:
            subprocess.run(base + settings + ['--query', GEN + f' FORMAT {fmt}'],
                           env=env, stdout=stream, check=True)
        files[fmt] = f'file({sql_string(path)}, {sql_string(fmt)}, {sql_string(STRUCT)})'
    print(f'Generated {N:,} events in Avro and Parquet.')

    projections = {'two': ['event_time', 'latency_ms'], 'all': NAMES}
    expected = {shape: digest(f"SELECT {', '.join(columns)} FROM ({GEN})")
                for shape, columns in projections.items()}
    checks = {}
    for fmt, source in files.items():
        checks[fmt] = {}
        for shape, columns in projections.items():
            sql = f"SELECT {', '.join(columns)} FROM {source}"
            checks[fmt][shape] = digest(sql)
            if checks[fmt][shape] != expected[shape]:
                raise RuntimeError(f'{fmt}/{shape} output differs from the generated data')
    (output / 'validation.json').write_text(json.dumps(
        {'status': 'pass', 'expected_sha256': expected, 'files': checks}, indent=2) + '\n')
    print('Both formats match the generated data for both projections.')

    rows = []
    print('\nFormat    Columns    Elapsed ms')
    for shape, columns in projections.items():
        for fmt, source in files.items():
            sql = f"SELECT {', '.join(columns)} FROM {source} FORMAT Null"
            (output / f'{fmt.lower()}-{shape}.sql').write_text(sql + ';\n')
            start = time.perf_counter()
            query(sql, stdout=subprocess.DEVNULL)
            elapsed = (time.perf_counter() - start) * 1000
            rows.append({'format': fmt, 'columns': len(columns), 'elapsed_ms': round(elapsed, 2)})
            print(f'{fmt:<10}{len(columns):<11}{elapsed:.2f}')
    with (output / 'results.csv').open('x', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['format', 'columns', 'elapsed_ms'])
        writer.writeheader()
        writer.writerows(rows)
    print(f'\nFiles, SQL, validation and timings saved to {output}')


if __name__ == '__main__':
    main()
