#!/usr/bin/env python3
"""Local endpoint selection and preflight controls; no Docker daemon access."""
import json
import unittest
from unittest.mock import patch
from reproduce import docker_target, runtime_platform

LOCAL = 'unix:///var/run/docker.sock'

def details(endpoint):
    return json.dumps([{'Endpoints': {'docker': {'Host': endpoint}}}])

class RuntimeTests(unittest.TestCase):
    def test_current_local_context(self):
        with patch('reproduce.subprocess.check_output', side_effect=['desktop-linux\n', details(LOCAL)]):
            command, target, _ = docker_target(environ={})
        self.assertEqual(command, ['docker', '--host', LOCAL])
        self.assertEqual(target['context'], 'desktop-linux')

    def test_explicit_context_overrides_environment(self):
        with patch('reproduce.subprocess.check_output', return_value=details(LOCAL)) as read:
            _, _, env = docker_target('local-test', environ={
                'DOCKER_HOST': 'tcp://production:2376', 'DOCKER_CONTEXT': 'production',
                'BUILDX_BUILDER': 'remote-builder', 'DOCKER_DEFAULT_PLATFORM': 'linux/s390x'})
        self.assertEqual(read.call_args.args[0][-1], 'local-test')
        self.assertFalse(any(key in env for key in ['DOCKER_HOST', 'DOCKER_CONTEXT', 'BUILDX_BUILDER', 'DOCKER_DEFAULT_PLATFORM']))

    def test_environment_context_takes_precedence_over_host(self):
        with patch('reproduce.subprocess.check_output', return_value=details(LOCAL)) as read:
            docker_target(environ={'DOCKER_CONTEXT': 'local-test', 'DOCKER_HOST': 'ssh://production'})
        self.assertEqual(read.call_args.args[0][-1], 'local-test')

    def test_local_host_override(self):
        with patch('reproduce.subprocess.check_output') as read:
            command, _, _ = docker_target(environ={'DOCKER_HOST': LOCAL})
        read.assert_not_called()
        self.assertEqual(command[-1], LOCAL)

    def test_remote_and_malformed_endpoints_refused_before_connection(self):
        for endpoint in ['tcp://production:2376', 'tcp://localhost:2375', 'ssh://production',
                         'unix://relative', 'npipe:////server/pipe/docker_engine']:
            with self.subTest(endpoint=endpoint), patch('reproduce.subprocess.check_output') as read:
                with self.assertRaisesRegex(RuntimeError, 'local Docker socket'):
                    docker_target(environ={'DOCKER_HOST': endpoint})
                read.assert_not_called()

    def test_remote_context_refused_after_metadata_only(self):
        with patch('reproduce.subprocess.check_output', return_value=details('ssh://production')) as read:
            with self.assertRaisesRegex(RuntimeError, 'local Docker socket'):
                docker_target('remote-test', environ={})
        self.assertEqual(read.call_count, 1)
        self.assertEqual(read.call_args.args[0][:3], ['docker', 'context', 'inspect'])

    def test_saved_endpoint_survives_context_switch(self):
        with patch('reproduce.subprocess.check_output') as read:
            command, _, _ = docker_target(saved={'context': 'local-test', 'docker_endpoint': LOCAL},
                                         environ={'DOCKER_CONTEXT': 'production'})
        read.assert_not_called()
        self.assertEqual(command[-1], LOCAL)

    def test_existing_run_cannot_switch_engines(self):
        with patch('reproduce.subprocess.check_output', return_value=details('unix:///other.sock')):
            with self.assertRaisesRegex(RuntimeError, 'refusing to switch engines'):
                docker_target('other-local', saved={'docker_endpoint': LOCAL}, environ={})

    def test_legacy_run_uses_its_saved_context(self):
        with patch('reproduce.subprocess.check_output', return_value=details(LOCAL)) as read:
            docker_target(saved={'context': 'old-local'}, environ={'DOCKER_CONTEXT': 'production'})
        self.assertEqual(read.call_args.args[0][-1], 'old-local')

    def test_local_windows_pipe_selection(self):
        pipe = 'npipe:////./pipe/dockerDesktopLinuxEngine'
        command, _, _ = docker_target(environ={'DOCKER_HOST': pipe})
        self.assertEqual(command[-1], pipe)

    def test_supported_native_platforms(self):
        for arch, expected in [('aarch64', 'arm64'), ('arm64', 'arm64'), ('x86_64', 'amd64'), ('amd64', 'amd64')]:
            info = {'OSType': 'linux', 'Architecture': arch, 'CgroupVersion': '2',
                    'NCPU': 2, 'MemTotal': 3 * 1024**3}
            self.assertEqual(runtime_platform(info), 'linux/' + expected)

    def test_unsupported_runtime_or_limits_refused(self):
        good = {'OSType': 'linux', 'Architecture': 'aarch64', 'CgroupVersion': '2',
                'NCPU': 2, 'MemTotal': 3 * 1024**3}
        for override in [{'OSType': 'windows'}, {'Architecture': 's390x'}, {'CgroupVersion': '1'},
                         {'NCPU': 1}, {'MemTotal': 2 * 1024**3}]:
            with self.subTest(override=override), self.assertRaises(RuntimeError):
                runtime_platform({**good, **override})

if __name__ == '__main__':
    unittest.main()
