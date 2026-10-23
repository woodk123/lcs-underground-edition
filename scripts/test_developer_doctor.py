"""Read-only prerequisite diagnostics must catch absent, stale and broken setup."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import developer_doctor as doctor


class DoctorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.pin = {'flutter_version': '1.2.3', 'flutter_revision': 'a' * 40}
        self.write('scripts/toolchain.json', self.pin)
        self.write('upstream/pubspec.yaml', 'name: lcs_new_age\n')
        self.write('upstream/lib/model.dart', "part 'model.g.dart';\n")
        self.write('upstream/lib/model.g.dart', '// generated fixture\n')
        self.sdk = self.root / '.tools/flutter'
        suffix = '.bat' if os.name == 'nt' else ''
        for name in (f'bin/flutter{suffix}', f'bin/dart{suffix}',
                     f'bin/cache/dart-sdk/bin/dart{".exe" if os.name == "nt" else ""}',
                     'bin/cache/flutter_tools.snapshot', '.git/HEAD'):
            self.write('.tools/flutter/' + name, 'fixture')
        self.version = {'frameworkVersion': self.pin['flutter_version'],
                        'frameworkRevision': self.pin['flutter_revision']}
        self.write('.tools/flutter/bin/cache/flutter.version.json', self.version)
        self.config = {'configVersion': 2, 'flutterVersion': self.pin['flutter_version'],
                       'flutterRoot': self.sdk.as_uri(),
                       'packages': [{'name': 'lcs_new_age', 'rootUri': '../', 'packageUri': 'lib/'}]}
        self.write('upstream/.dart_tool/package_config.json', self.config)
        self.make_node_package('offline_test')
        self.make_node_package('dev_mcp')
        self.write('scripts/requirements-art.txt', '# pinned tooling prerequisite\nPillow==1.2.3\n')

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, (dict, list)) else value, encoding='utf-8')
        return path

    def make_node_package(self, name):
        directory = f'upstream/tool/{name}'
        manifest = {'dependencies': {'@scope/example': '^1.0.0'}, 'engines': {'node': '>=20'}}
        self.write(f'{directory}/package.json', manifest)
        lock = {'lockfileVersion': 3, 'packages': {'': manifest,
                'node_modules/@scope/example': {'version': '1.1.0', 'engines': {'node': '>=20'}},
                'node_modules/transitive': {'version': '2.3.4'}}}
        self.write(f'{directory}/package-lock.json', lock)
        self.write(f'{directory}/node_modules/@scope/example/package.json', {'version': '1.1.0'})
        self.write(f'{directory}/node_modules/transitive/package.json', {'version': '2.3.4'})

    def test_bootstrapped_pinned_sdk_passes_without_invoking_flutter(self):
        with patch.object(doctor.subprocess, 'check_output', return_value=self.pin['flutter_revision'] + '\n') as run:
            self.assertIn('1.2.3', doctor.check_flutter(self.root))
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0], ['git', '--no-optional-locks', '-C', str(self.sdk),
                                                     'rev-parse', '--verify', 'HEAD'])
            self.assertEqual(run.call_args.kwargs['timeout'], 15)

    def test_stale_sdk_cache_and_actual_revision_mismatch_fail(self):
        path = self.root / '.tools/flutter/bin/cache/flutter.version.json'
        for field in self.version:
            with self.subTest(field=field):
                self.write(str(path.relative_to(self.root)), {**self.version, field: 'old'})
                with patch.object(doctor.subprocess, 'check_output') as run:
                    with self.assertRaisesRegex(ValueError, 'cache differs'):
                        doctor.check_flutter(self.root)
                    run.assert_not_called()
        self.write(str(path.relative_to(self.root)), self.version)
        with patch.object(doctor.subprocess, 'check_output', return_value='b' * 40):
            with self.assertRaisesRegex(ValueError, 'cached version metadata may be stale'):
                doctor.check_flutter(self.root)

    def test_missing_uninitialized_or_non_git_sdk_fails_before_query(self):
        paths = [self.sdk / 'bin/cache/flutter_tools.snapshot', self.sdk / '.git']
        for path in paths:
            with self.subTest(path=path):
                hidden = path.with_name(path.name + '.held')
                path.rename(hidden)
                try:
                    with patch.object(doctor.subprocess, 'check_output') as run:
                        with self.assertRaises(ValueError):
                            doctor.check_flutter(self.root)
                        run.assert_not_called()
                finally:
                    hidden.rename(path)

    def test_dart_dependency_roots_match_current_checkout_and_pin(self):
        self.assertIn('1 resolved package', doctor.check_dart_packages(self.root))
        for field, value in [('flutterVersion', 'old'), ('flutterRoot', (self.root / 'other-sdk').as_uri())]:
            with self.subTest(field=field):
                self.write('upstream/.dart_tool/package_config.json', {**self.config, field: value})
                with self.assertRaisesRegex(ValueError, 'different Flutter SDK or checkout'):
                    doctor.check_dart_packages(self.root)
        self.config['packages'].append({'name': 'deleted-cache', 'rootUri': (self.root / 'absent').as_uri()})
        self.write('upstream/.dart_tool/package_config.json', self.config)
        with self.assertRaisesRegex(ValueError, 'deleted-cache'):
            doctor.check_dart_packages(self.root)

    def test_app_package_must_be_unique_and_resolve_to_this_checkout(self):
        foreign = self.root / 'other checkout/upstream'
        foreign.mkdir(parents=True)
        dependency = self.root / 'existing dependency'
        dependency.mkdir()
        app = self.config['packages'][0]
        variants = [
            ([{'name': 'some_dependency', 'rootUri': dependency.as_uri()}], 'exactly one lcs_new_age'),
            ([app, app], 'exactly one lcs_new_age'),
            ([app, {**app, 'rootUri': foreign.as_uri()}], 'exactly one lcs_new_age'),
            ([{**app, 'rootUri': foreign.as_uri()}], 'different checkout'),
        ]
        for packages, message in variants:
            with self.subTest(packages=packages):
                self.write('upstream/.dart_tool/package_config.json', {**self.config, 'packages': packages})
                with self.assertRaisesRegex(ValueError, message):
                    doctor.check_dart_packages(self.root)

    def test_app_package_name_comes_from_the_current_pubspec(self):
        self.write('upstream/pubspec.yaml', "name: 'renamed_lcs' # authoritative package name\n")
        self.config['packages'][0]['name'] = 'renamed_lcs'
        self.write('upstream/.dart_tool/package_config.json', self.config)
        self.assertIn('1 resolved package', doctor.check_dart_packages(self.root))
        self.config['packages'][0]['name'] = 'lcs_new_age'
        self.write('upstream/.dart_tool/package_config.json', self.config)
        with self.assertRaisesRegex(ValueError, 'exactly one renamed_lcs'):
            doctor.check_dart_packages(self.root)

    def test_missing_duplicate_or_invalid_pubspec_package_name_is_explicit(self):
        for manifest in ('description: no name\n', 'name: first\nname: second\n', 'name: [not_a_scalar]\n'):
            with self.subTest(manifest=manifest):
                self.write('upstream/pubspec.yaml', manifest)
                with self.assertRaisesRegex(ValueError, 'package name.*upstream/pubspec.yaml'):
                    doctor.check_dart_packages(self.root)

    def test_package_uris_support_spaces_but_reject_network_and_nonlocal_roots(self):
        directory = self.root / 'cache with spaces'
        directory.mkdir()
        base = self.root / 'upstream/.dart_tool/package_config.json'
        self.assertEqual(doctor.local_uri(base, directory.as_uri()), directory)
        for value in (None, '', 'https://example.invalid/cache', 'file://remote/path', 'file:///cache?query'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                doctor.local_uri(base, value)

    def test_missing_generated_outputs_fail_inventory_with_pinned_generation_remedy(self):
        (self.root / 'upstream/lib/model.g.dart').unlink()
        self.write('upstream/lib/second.dart', 'part "second.g.dart";\n')
        (self.root / 'upstream/lib/second.g.dart').mkdir()
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        with patch.object(doctor.subprocess, 'check_output', return_value=self.pin['flutter_revision']) as subprocess_call:
            report = doctor.diagnose(self.root)
        self.assertEqual(report['status'], 'failed')
        generated = next(check for check in report['checks'] if check['name'] == 'generated-sources')
        self.assertEqual(generated['status'], 'failed')
        self.assertIn('upstream/lib/model.g.dart', generated['detail'])
        self.assertIn('upstream/lib/second.g.dart', generated['detail'])
        self.assertIn('non-file', generated['detail'])
        self.assertIn('build_runner build', generated['remedy'])
        self.assertIn('.tools', generated['remedy'])
        self.assertEqual(subprocess_call.call_count, 1, 'Only the existing read-only SDK Git check may run.')
        self.assertEqual({path.relative_to(self.root): path.read_bytes()
                          for path in self.root.rglob('*') if path.is_file()}, before)

    def test_generated_presence_skips_generated_contents_and_claims_no_freshness(self):
        path = self.root / 'upstream/lib/model.g.dart'
        path.write_bytes(b'\xff generated contents need not be parsed\npart "nested.g.dart";\n')
        os.utime(path, (1, 1))
        with patch.object(doctor.subprocess, 'check_output') as run:
            detail = doctor.check_generated_sources(self.root)
        run.assert_not_called()
        self.assertIn('1 referenced .g.dart output', detail)
        self.assertIn('presence only', detail)
        self.assertIn('freshness not checked', detail)

    def test_generated_presence_recognizes_source_parts_and_ignores_other_directives(self):
        self.write('upstream/lib/model.dart',
                   '// part "commented.g.dart";\n'
                   'part of "parent.g.dart";\n'
                   'part "hand_authored.dart";\n'
                   'part "model.g.dart"; // source-authored serializer reference\n')
        self.assertIn('1 referenced .g.dart output', doctor.check_generated_sources(self.root))

    def test_generated_presence_rejects_source_directory_missing_or_part_escape(self):
        (self.root / 'upstream/lib/model.dart').unlink()
        (self.root / 'upstream/lib/model.g.dart').unlink()
        (self.root / 'upstream/lib').rmdir()
        with self.assertRaisesRegex(ValueError, 'source directory'):
            doctor.check_generated_sources(self.root)
        self.write('outside.g.dart', 'exists but is not generated source for this library')
        self.write('upstream/lib/model.dart', "part '../../outside.g.dart';\n")
        with self.assertRaisesRegex(ValueError, 'escapes upstream/lib'):
            doctor.check_generated_sources(self.root)

    def test_lock_checks_transitive_and_scoped_versions_and_missing_installations(self):
        self.assertIn('2 installed package versions', doctor.check_node_packages(self.root, 'offline_test', 'v20.0.0'))
        path = self.root / 'upstream/tool/offline_test/node_modules/transitive/package.json'
        path.write_text('{"version":"old"}')
        with self.assertRaisesRegex(ValueError, 'transitive differs'):
            doctor.check_node_packages(self.root, 'offline_test', 'v20.0.0')
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            doctor.check_node_packages(self.root, 'offline_test', 'v20.0.0')

    def test_old_node_and_stale_manifest_lock_fail(self):
        with self.assertRaisesRegex(ValueError, 'does not meet.*>=20'):
            doctor.check_node_packages(self.root, 'dev_mcp', 'v19.9.9')
        self.write('upstream/tool/dev_mcp/package.json', {'dependencies': {'new-package': '1.0.0'}})
        with self.assertRaisesRegex(ValueError, 'differs from package-lock'):
            doctor.check_node_packages(self.root, 'dev_mcp', 'v20.0.0')

    def test_root_node_engines_must_match_the_manifest_and_lock(self):
        directory = 'upstream/tool/dev_mcp'
        manifest = json.loads((self.root / directory / 'package.json').read_text())
        lock = json.loads((self.root / directory / 'package-lock.json').read_text())
        for declared, locked in [({'node': '>=22'}, {'node': '>=20'}),
                                 ({}, {'node': '>=20'}), ({'node': '>=20'}, {})]:
            with self.subTest(declared=declared, locked=locked):
                self.write(f'{directory}/package.json', {**manifest, 'engines': declared})
                lock['packages']['']['engines'] = locked
                self.write(f'{directory}/package-lock.json', lock)
                with self.assertRaisesRegex(ValueError, 'package.json engines differs from package-lock'):
                    doctor.check_node_packages(self.root, 'dev_mcp', 'v20.0.0')

    def test_matching_root_node_engine_rejects_older_runtime_versions(self):
        directory = 'upstream/tool/dev_mcp'
        manifest = json.loads((self.root / directory / 'package.json').read_text())
        lock = json.loads((self.root / directory / 'package-lock.json').read_text())
        manifest['engines'] = lock['packages']['']['engines'] = {'node': '>=22.2.1'}
        self.write(f'{directory}/package.json', manifest)
        self.write(f'{directory}/package-lock.json', lock)
        for version in ('v22.2.0', 'v22.1.9', 'v21.99.99'):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'does not meet dev_mcp: >=22.2.1'):
                doctor.check_node_packages(self.root, 'dev_mcp', version)
        for version in ('v22.2.1', 'v23.0.0'):
            with self.subTest(version=version):
                self.assertIn('2 installed package versions', doctor.check_node_packages(self.root, 'dev_mcp', version))

    def test_lock_path_cannot_escape_and_unsupported_engine_is_explicit(self):
        path = self.root / 'upstream/tool/dev_mcp/package-lock.json'
        lock = json.loads(path.read_text())
        lock['packages']['node_modules/../../elsewhere'] = {'version': '1.0.0'}
        self.write(str(path.relative_to(self.root)), lock)
        with self.assertRaisesRegex(ValueError, 'Invalid locked package path'):
            doctor.check_node_packages(self.root, 'dev_mcp', 'v20.0.0')
        del lock['packages']['node_modules/../../elsewhere']
        lock['packages']['node_modules/@scope/example']['engines']['node'] = '^20 || >=22'
        self.write(str(path.relative_to(self.root)), lock)
        with self.assertRaisesRegex(ValueError, 'needs manual review'):
            doctor.check_node_packages(self.root, 'dev_mcp', 'v20.0.0')

    def test_optional_missing_package_is_permitted(self):
        path = self.root / 'upstream/tool/dev_mcp/package-lock.json'
        lock = json.loads(path.read_text())
        lock['packages']['node_modules/optional'] = {
            'version': '1.0.0', 'optional': True, 'engines': {'node': '>=99'}}
        self.write(str(path.relative_to(self.root)), lock)
        self.assertIn('2 installed package versions', doctor.check_node_packages(self.root, 'dev_mcp', 'v20.0.0'))

    def test_invalid_npm_and_dart_metadata_are_reported_without_tracebacks(self):
        config_path = 'upstream/.dart_tool/package_config.json'
        for config in ([], {'configVersion': 2, 'packages': []},
                       {**self.config, 'packages': ['bad-package']},
                       {**self.config, 'packages': [{'name': 'bad-uri', 'rootUri': 7}]}):
            with self.subTest(config=config):
                self.write(config_path, config)
                report = doctor.diagnose(self.root)
                self.assertEqual(report['checks'][1]['status'], 'failed')
        self.write(config_path, self.config)
        lock_path = 'upstream/tool/dev_mcp/package-lock.json'
        original = json.loads((self.root / lock_path).read_text())
        for value in (None, [], 'broken'):
            with self.subTest(engines=value):
                lock = json.loads(json.dumps(original))
                lock['packages']['node_modules/@scope/example']['engines'] = value
                self.write(lock_path, lock)
                with patch.object(doctor, 'check_node', return_value='v20.0.0'):
                    report = doctor.diagnose(self.root, mcp=True)
                check = next(item for item in report['checks'] if item['name'] == 'mcp-packages')
                self.assertEqual(check['status'], 'failed')
                self.assertIn('Invalid locked engines', check['detail'])

    def test_node_missing_malformed_failing_and_timeout_paths(self):
        with patch.object(doctor.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'not on PATH'):
                doctor.check_node()
        with patch.object(doctor.shutil, 'which', return_value='node'):
            for response in ('noise', 'v20', subprocess.TimeoutExpired('node', 15),
                             subprocess.CalledProcessError(1, ['node'])):
                with self.subTest(response=response):
                    with patch.object(doctor.subprocess, 'check_output') as run:
                        if isinstance(response, Exception):
                            run.side_effect = response
                        else:
                            run.return_value = response
                        with self.assertRaises((ValueError, subprocess.SubprocessError)):
                            doctor.check_node()

    def test_pillow_pin_is_read_from_requirements_for_this_interpreter(self):
        with patch.object(doctor.metadata, 'version', return_value='1.2.3'):
            self.assertIn('Pillow 1.2.3', doctor.check_pillow(self.root))
        for response in ('old', doctor.metadata.PackageNotFoundError('Pillow')):
            with patch.object(doctor.metadata, 'version') as version:
                if isinstance(response, Exception):
                    version.side_effect = response
                else:
                    version.return_value = response
                with self.assertRaises(ValueError):
                    doctor.check_pillow(self.root)

    def test_default_does_not_require_optional_tools_and_inspection_writes_nothing(self):
        before = {str(path.relative_to(self.root)): path.read_bytes()
                  for path in self.root.rglob('*') if path.is_file()}
        with patch.object(doctor.subprocess, 'check_output', return_value=self.pin['flutter_revision']), \
                patch.object(doctor, 'check_node') as node, patch.object(doctor, 'check_pillow') as pillow:
            report = doctor.diagnose(self.root)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual([item['name'] for item in report['checks']], ['flutter', 'dart-packages', 'generated-sources'])
        node.assert_not_called()
        pillow.assert_not_called()
        self.assertEqual(before, {str(path.relative_to(self.root)): path.read_bytes()
                                  for path in self.root.rglob('*') if path.is_file()})

    def test_independent_failures_collect_remedies_and_malformed_data_does_not_traceback(self):
        self.write('.tools/flutter/bin/cache/flutter.version.json', [])
        self.write('upstream/.dart_tool/package_config.json', {'configVersion': 2, 'packages': 'bad'})
        with patch.object(doctor, 'check_node', side_effect=ValueError('missing node')), \
                patch.object(doctor, 'check_pillow', side_effect=ValueError('missing pillow')):
            report = doctor.diagnose(self.root, mcp=True, tooling=True)
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(len(report['checks']), 7)
        failures = [item for item in report['checks'] if item['status'] == 'failed']
        self.assertEqual(len(failures), 4)
        self.assertTrue(all(item['remedy'] for item in failures))

    def test_json_cli_and_nonzero_exit_are_machine_readable(self):
        with patch.object(doctor, 'ROOT', self.root), \
                patch.object(doctor.subprocess, 'check_output', return_value=self.pin['flutter_revision']):
            output = io.StringIO()
            with redirect_stdout(output):
                code = doctor.main(['--json'])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(output.getvalue())['status'], 'passed')
            self.write('upstream/.dart_tool/package_config.json', 'interrupted')
            output = io.StringIO()
            with redirect_stdout(output):
                code = doctor.main(['--json'])
            self.assertEqual(code, 1)
            self.assertEqual(json.loads(output.getvalue())['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
