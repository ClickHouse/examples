"""Focused script regressions; no network, model requests or Cloud changes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

EXAMPLE = Path(__file__).resolve().parents[1]

STUB = r"""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {'name': name, 'args': args}
if name == 'claude':
    entry['prompt'] = sys.stdin.read()
if name == 'clickhouse':
    entry['password'] = os.environ.get('CLICKHOUSE_PASSWORD')
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps(entry) + '\n')
if name == 'clickhousectl':
    if args[:3] == ['cloud', 'service', 'query']:
        if os.environ.get('QUERY_FAIL'):
            print('Query API unavailable', file=sys.stderr)
            sys.exit(1)
        print(os.environ.get('SNAPSHOT', '200\t0\t350'))
    elif args[:3] == ['cloud', 'service', 'prometheus']:
        if os.environ.get('METRICS_FAIL'):
            print('metrics request failed', file=sys.stderr)
            sys.exit(1)
        print(os.environ.get('METRICS', 'ClickHouseMetrics_Query{replica="one"} 4'))
    else:
        print('Unexpected command: ' + repr(args), file=sys.stderr)
        sys.exit(90)
elif name == 'clickhouse':
    if args[0] == 'client':
        print('simulated query failure', file=sys.stderr)
        sys.exit(23)
elif name == 'claude':
    print('Agent invoked')
    sys.exit(int(os.environ.get('AGENT_EXIT', '0')))
"""


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.calls = self.directory / 'calls.jsonl'
        for name in ('clickhousectl', 'clickhouse', 'claude'):
            executable = self.directory / name
            executable.write_text(STUB)
            executable.chmod(0o755)
        self.env = {
            **os.environ,
            'PATH': str(self.directory) + os.pathsep + os.environ['PATH'],
            'CALL_LOG': str(self.calls),
            'SERVICE_ID': 'demo-service',
            'CH_HOST': 'demo.invalid',
            'CH_PASSWORD': 'test-only-secret',
            'CH_USER': 'default',
            'CH_PORT': '9440',
            'SLA_MS': '200',
            'MIN_SAMPLES': '100',
            'CLAUDE_MODEL': 'test-model',
        }
        for key in ('QUERY_FAIL', 'METRICS_FAIL', 'METRICS', 'SNAPSHOT', 'AGENT_EXIT'):
            self.env.pop(key, None)

    def run_script(self, script, *args, **env):
        result = subprocess.run(
            ['bash', str(EXAMPLE / script), *args],
            cwd=self.directory, env={**self.env, **env},
            capture_output=True, text=True, timeout=10,
        )
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return result, calls

    def test_empty_and_undersampled_windows_do_not_start_agent(self):
        for snapshot, status in [('0\t0\t0', 'NO_DATA'), ('0\t7\t0', 'NO_DATA'),
                                 ('99\t0\t900', 'INSUFFICIENT_SAMPLES')]:
            with self.subTest(snapshot=snapshot):
                result, calls = self.run_script('investigate.sh', SNAPSHOT=snapshot)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(status, result.stdout)
                self.assertFalse(any(c['name'] == 'claude' for c in calls))
                if snapshot.startswith('0\t'):
                    self.assertIn('p99=n/a', result.stdout)

    def test_target_equality_is_not_a_breach(self):
        result, calls = self.run_script('investigate.sh', SNAPSHOT='100\t0\t200')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('OK', result.stdout)
        self.assertFalse(any(c['name'] == 'claude' for c in calls))

    def test_valid_breach_handoff(self):
        result, calls = self.run_script('investigate.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        query, agent = calls
        self.assertIn('--no-auto-enable', query['args'])
        self.assertIn(str(EXAMPLE / 'sla.sql'), query['args'])
        self.assertEqual(agent['name'], 'claude')
        self.assertEqual(agent['args'][agent['args'].index('--model') + 1], 'test-model')
        self.assertEqual(agent['args'][agent['args'].index('--tools') + 1], 'Bash')
        self.assertIn('--strict-mcp-config', agent['args'])
        self.assertIn('{"mcpServers":{}}', agent['args'])
        self.assertIn('Bash(clickhousectl cloud service scale demo-service *)', agent['args'])
        self.assertNotIn('Bash(clickhousectl:*)', agent['args'])
        self.assertIn('make NO change', agent['prompt'])
        self.assertIn('p99=350ms', agent['prompt'])
        self.assertIn('AT MOST ONE', agent['prompt'])
        self.assertIn('3 replicas or 32 GiB', agent['prompt'])

    def test_failed_snapshot_never_starts_agent(self):
        result, calls = self.run_script('investigate.sh', QUERY_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Query API unavailable', result.stderr)
        self.assertFalse(any(c['name'] == 'claude' for c in calls))

    def test_malformed_responses_are_not_latency(self):
        for snapshot in ('', 'NaN', 'null', '100\t0\tNaN', '100\t0\t300\n100\t0\t400',
                         '100\t0\t300\textra', 'error from proxy'):
            with self.subTest(snapshot=snapshot):
                result, calls = self.run_script('investigate.sh', SNAPSHOT=snapshot)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Unexpected SLA response', result.stderr)
                self.assertFalse(any(c['name'] == 'claude' for c in calls))

    def test_agent_failure_is_propagated(self):
        result, _ = self.run_script('investigate.sh', AGENT_EXIT='7')
        self.assertEqual(result.returncode, 7)

    def test_watch_shows_latency_failures_and_replica_metrics(self):
        metrics = '\n'.join(['# TYPE ClickHouseMetrics_Query gauge',
                             'ClickHouseMetrics_Query{replica="one"} 4',
                             'ClickHouseAsyncMetrics_CGroupMemoryUsed{replica="two"} 2048',
                             'ClickHouseProfileEvents_OSCPUWaitMicroseconds 40', 'unrelated_metric 99'])
        result, _ = self.run_script('watch.sh', '--once', SNAPSHOT='200\t3\t100', METRICS=metrics)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('OK p99=100ms', result.stdout)
        self.assertIn('failed=3', result.stdout)
        self.assertIn('investigate them', result.stdout)
        self.assertIn('replica="one"', result.stdout)
        self.assertIn('replica="two"', result.stdout)
        self.assertIn('OSCPUWaitMicroseconds 40', result.stdout)
        self.assertNotIn('unrelated_metric', result.stdout)

    def test_watch_api_failure_is_unknown(self):
        result, _ = self.run_script('watch.sh', '--once', QUERY_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('UNKNOWN', result.stderr)
        self.assertNotIn('OK', result.stdout)

    def test_watch_empty_window(self):
        result, _ = self.run_script('watch.sh', '--once', SNAPSHOT='0\t0\t0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('NO_DATA p99=n/a', result.stdout)

    def test_watch_missing_or_failed_metrics_are_visible(self):
        result, _ = self.run_script('watch.sh', '--once', METRICS='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No matching pressure metrics', result.stderr)
        result, _ = self.run_script('watch.sh', '--once', METRICS_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pressure is unknown', result.stderr)

    def test_invalid_configuration_stops_before_any_command(self):
        for config in ({'SLA_MS': '0'}, {'SLA_MS': '08'}, {'MIN_SAMPLES': '-2'},
                       {'SLA_MS': '1+1'}, {'SERVICE_ID': 'id;echo unsafe'}):
            with self.subTest(config=config):
                result, calls = self.run_script('investigate.sh', **config)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_invalid_load_arguments_stop_before_any_command(self):
        for args in [('invalid',), ('horizontal', '0'), ('vertical', '-1'),
                     ('horizontal', '1;echo unsafe'), ('vertical', '4', 'extra')]:
            with self.subTest(args=args):
                result, calls = self.run_script('load.sh', *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_load_modes_use_shared_sql_and_password_environment(self):
        for mode, filename, concurrency in [('horizontal', 'dashboard.sql', '256'),
                                            ('vertical', 'analytics.sql', '4')]:
            with self.subTest(mode=mode):
                result, calls = self.run_script('load.sh', mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = calls[-1]
                self.assertEqual(call['args'][0], 'benchmark')
                self.assertEqual(call['args'][call['args'].index('--query') + 1],
                                 (EXAMPLE / filename).read_text().rstrip('\n'))
                self.assertEqual(call['args'][call['args'].index('--concurrency') + 1], concurrency)
                self.assertNotIn(self.env['CH_PASSWORD'], call['args'])
                self.assertEqual(call['password'], self.env['CH_PASSWORD'])

    def test_frontend_uses_same_sql_and_exits_on_query_failure(self):
        result, calls = self.run_script('frontend.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('simulated query failure', result.stderr)
        self.assertTrue(calls)
        for call in calls:
            self.assertEqual(call['name'], 'clickhouse')
            self.assertEqual(call['args'][call['args'].index('--query') + 1],
                             (EXAMPLE / 'dashboard.sql').read_text().rstrip('\n'))
            self.assertNotIn(self.env['CH_PASSWORD'], call['args'])


if __name__ == '__main__':
    unittest.main()
