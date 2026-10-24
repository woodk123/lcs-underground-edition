"""MCP dependency reuse requires the complete locked installation, not root folders."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import developer_doctor as doctor
import prepare_dev_mcp as prepare
from release_common import digest, file_hashes, write_json


class DependencyReadinessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs dependency cache ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.output = self.root / '.local/dev-mcp'
        self.output.mkdir(parents=True)
        self.marker = self.output / 'dependencies.json'
        self.locks = {}
        self.package('offline_test', {'dependencies': {'playwright': '1.64.1'}}, {
            'node_modules/playwright': {'version': '1.64.1', 'engines': {'node': '>=18'}},
            'node_modules/playwright-core': {'version': '1.64.1', 'engines': {'node': '>=18'}},
        })
        self.package('dev_mcp', {
            'dependencies': {'@modelcontextprotocol/server': '2.3.1', 'zod': '4.6.7'},
            'devDependencies': {'@modelcontextprotocol/client': '2.3.1'},
            'engines': {'node': '>=20'},
        }, {
            'node_modules/@modelcontextprotocol/server': {'version': '2.3.1', 'engines': {'node': '>=20'}},
            'node_modules/@modelcontextprotocol/client': {'version': '2.3.1', 'dev': True},
            'node_modules/zod': {'version': '4.6.7'},
        })
        self.refresh_marker()
        npm = patch.object(prepare.shutil, 'which', return_value='npm-fixture')
        npm.start()
        self.addCleanup(npm.stop)
        node = patch.object(prepare, 'check_node', return_value='v22.19.0')
        self.node = node.start()
        self.addCleanup(node.stop)
        run = patch.object(prepare, 'run', side_effect=self.install)
        self.run = run.start()
        self.addCleanup(run.stop)

    def directory(self, package):
        return self.root / 'upstream/tool' / package

    def package(self, name, manifest, dependencies):
        directory = self.directory(name)
        directory.mkdir(parents=True)
        write_json(directory / 'package.json', manifest)
        self.locks[name] = {'lockfileVersion': 3, 'packages': {'': manifest, **dependencies}}
        write_json(directory / 'package-lock.json', self.locks[name])
        self.install_package(name)

    def install_package(self, package):
        for name, metadata in self.locks[package]['packages'].items():
            if name and not metadata.get('optional'):
                destination = self.directory(package) / name / 'package.json'
                destination.parent.mkdir(parents=True, exist_ok=True)
                write_json(destination, {'version': metadata['version']})

    def install(self, command, cwd):
        self.assertEqual(command[:2], ['npm-fixture', 'ci'])
        self.assertEqual(cwd, self.root)
        self.assertIn('--include=dev', command)
        directory = Path(command[command.index('--prefix') + 1])
        self.assertEqual(directory.parent, self.root / 'upstream/tool')
        self.install_package(directory.name)

    def refresh_marker(self):
        write_json(self.marker, {name: digest(self.directory(name) / 'package-lock.json') for name in self.locks})

    def stale_marker(self, package):
        previous = json.loads(self.marker.read_text())
        previous[package] = 'previous lock hash'
        write_json(self.marker, previous)
        return self.marker.read_bytes()

    def remove_installed(self, package, name):
        path = self.directory(package) / name / 'package.json'
        path.unlink()
        path.parent.rmdir()

    def assert_targeted_repair(self, package):
        prepare.install_dependencies(self.root, self.output)
        self.node.assert_called_once()
        self.run.assert_called_once()
        self.assertEqual(self.run.call_args.args[0],
                         ['npm-fixture', 'ci', '--prefix', str(self.directory(package)),
                          '--include=dev', '--no-audit', '--no-fund'])
        for name in self.locks:
            doctor.check_node_packages(self.root, name, self.node.return_value)
        self.assertEqual(json.loads(self.marker.read_text()),
                         {name: digest(self.directory(name) / 'package-lock.json') for name in self.locks})

    def test_healthy_same_lock_inventory_skips_npm(self):
        prepare.install_dependencies(self.root, self.output)
        self.node.assert_called_once()
        self.run.assert_not_called()

    def test_missing_browser_transitive_repairs_only_browser_dependencies(self):
        self.remove_installed('offline_test', 'node_modules/playwright-core')
        self.assertTrue((self.directory('offline_test') / 'node_modules/playwright').is_dir())
        self.assert_targeted_repair('offline_test')

    def test_missing_server_runtime_repairs_only_mcp_dependencies(self):
        self.remove_installed('dev_mcp', 'node_modules/zod')
        self.assertTrue((self.directory('dev_mcp') / 'node_modules/@modelcontextprotocol/server').is_dir())
        self.assert_targeted_repair('dev_mcp')

    def test_missing_dev_client_is_repaired_even_with_production_environment(self):
        self.remove_installed('dev_mcp', 'node_modules/@modelcontextprotocol/client')
        with patch.dict('os.environ', {'NODE_ENV': 'production', 'npm_config_omit': 'dev'}):
            self.assert_targeted_repair('dev_mcp')

    def test_wrong_installed_version_repairs_only_mcp_dependencies(self):
        write_json(self.directory('dev_mcp') / 'node_modules/zod/package.json', {'version': 'old'})
        self.assert_targeted_repair('dev_mcp')

    def test_changed_lock_reinstalls_only_its_package(self):
        self.locks['dev_mcp']['fixture_revision'] = 'changed lock identity'
        write_json(self.directory('dev_mcp') / 'package-lock.json', self.locks['dev_mcp'])
        self.assert_targeted_repair('dev_mcp')

    def test_failed_npm_preserves_marker_without_claiming_new_readiness(self):
        before = self.stale_marker('dev_mcp')
        self.run.side_effect = subprocess.CalledProcessError(1, ['npm-fixture', 'ci'])
        with self.assertRaises(subprocess.CalledProcessError):
            prepare.install_dependencies(self.root, self.output)
        self.run.assert_called_once()
        self.assertEqual(self.marker.read_bytes(), before)

    def test_successful_but_incomplete_install_does_not_refresh_marker(self):
        self.remove_installed('dev_mcp', 'node_modules/@modelcontextprotocol/client')
        before = self.stale_marker('dev_mcp')
        self.run.side_effect = None
        with self.assertRaisesRegex(OSError, 'client'):
            prepare.install_dependencies(self.root, self.output)
        self.run.assert_called_once()
        self.assertEqual(self.marker.read_bytes(), before)

    def test_old_node_does_not_reinstall_healthy_packages_even_with_stale_marker(self):
        before = self.stale_marker('dev_mcp')
        self.node.return_value = 'v19.9.9'
        with self.assertRaisesRegex(ValueError, 'does not meet dev_mcp: >=20'):
            prepare.install_dependencies(self.root, self.output)
        self.run.assert_not_called()
        self.assertEqual(self.marker.read_bytes(), before)

    def test_actual_declared_node_requirement_fails_before_reinstall(self):
        manifest = self.locks['dev_mcp']['packages']['']
        manifest['engines'] = {'node': '>=24'}
        write_json(self.directory('dev_mcp') / 'package.json', manifest)
        write_json(self.directory('dev_mcp') / 'package-lock.json', self.locks['dev_mcp'])
        before = self.marker.read_bytes()
        with self.assertRaisesRegex(ValueError, 'does not meet dev_mcp: >=24'):
            prepare.install_dependencies(self.root, self.output)
        self.run.assert_not_called()
        self.assertEqual(self.marker.read_bytes(), before)

    def test_runtime_failure_after_repair_does_not_repeat_npm_on_retry(self):
        self.remove_installed('dev_mcp', 'node_modules/@modelcontextprotocol/client')
        before = self.stale_marker('dev_mcp')
        self.node.return_value = 'v19.9.9'
        for attempt in range(2):
            with self.subTest(attempt=attempt), self.assertRaisesRegex(ValueError, 'does not meet dev_mcp: >=20'):
                prepare.install_dependencies(self.root, self.output)
            self.assertEqual(self.run.call_count, 1)
            self.assertEqual(self.marker.read_bytes(), before)

    def test_missing_optional_platform_package_keeps_cache_reusable(self):
        self.locks['offline_test']['packages']['node_modules/optional-native'] = {
            'version': '1.0.0', 'optional': True, 'os': ['darwin'], 'engines': {'node': '>=99'}}
        write_json(self.directory('offline_test') / 'package-lock.json', self.locks['offline_test'])
        self.refresh_marker()
        prepare.install_dependencies(self.root, self.output)
        self.run.assert_not_called()

    def test_non_object_marker_is_replaced_after_validated_installs(self):
        write_json(self.marker, [])
        prepare.install_dependencies(self.root, self.output)
        self.assertEqual(self.run.call_count, 2)
        self.assertEqual(json.loads(self.marker.read_text()),
                         {name: digest(self.directory(name) / 'package-lock.json') for name in self.locks})

    def compiled_fixture(self):
        web = self.output / 'web'
        web.mkdir()
        for name in ('index.html', 'main.dart.js', 'sw.js'):
            (web / name).write_text('synthetic compiled fixture ' + name)
        source = {'commit': 'a' * 40, 'inputs_sha256': 'b' * 64}
        info = {'schema': 1, 'status': 'ready', 'devtools': True, 'source': source,
                'web_root': str(web), 'build_id': 'aaaaaaaa-bbbbbbbb',
                'main_js_sha256': digest(web / 'main.dart.js'), 'payload_hashes': file_hashes(web)}
        write_json(self.output / 'build.json', info)
        return web, source, info

    def test_dependency_repair_preserves_compiled_payload_and_cache_metadata(self):
        web, source, info = self.compiled_fixture()
        original_manifest = (self.output / 'build.json').read_bytes()
        self.remove_installed('dev_mcp', 'node_modules/zod')
        self.assertEqual(prepare.cached_build(self.output / 'build.json', source, web), info)
        self.assert_targeted_repair('dev_mcp')
        self.assertEqual(file_hashes(web), info['payload_hashes'])
        self.assertEqual((self.output / 'build.json').read_bytes(), original_manifest)
        self.assertEqual(prepare.cached_build(self.output / 'build.json', source, web), info)

    def test_check_cli_only_validates_compiled_cache_and_writes_nothing(self):
        web, source, info = self.compiled_fixture()
        self.remove_installed('dev_mcp', 'node_modules/@modelcontextprotocol/client')
        self.node.side_effect = AssertionError('--check must not inspect Node or install dependencies')
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        output = io.StringIO()
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'source_identity', return_value=source), \
                patch.object(sys, 'argv', ['prepare_dev_mcp.py', '--check', '--out', str(self.output)]), \
                redirect_stdout(output):
            prepare.main()
        self.assertEqual(json.loads(output.getvalue()),
                         {**{key: info[key] for key in ('web_root', 'build_id', 'main_js_sha256', 'source')},
                          'checked_source': source})
        self.node.assert_not_called()
        self.run.assert_not_called()
        self.assertEqual({path.relative_to(self.root): path.read_bytes()
                          for path in self.root.rglob('*') if path.is_file()}, before)


if __name__ == '__main__':
    unittest.main()
