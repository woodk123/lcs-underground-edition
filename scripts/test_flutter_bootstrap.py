"""Local SDK entrypoints must survive cold stdout without changing player source."""
from argparse import Namespace
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import build_linux
import prepare_dev_mcp as prepare
from release_common import digest, file_hashes


SCRIPTS = Path(__file__).resolve().parent
CHECK_OUTPUT = subprocess.check_output
FAKE_TOOL = r'''
import json
from pathlib import Path
import sys

sdk = Path(__file__).resolve().parent.parent
args = sys.argv[1:]
with (sdk / 'calls.jsonl').open('a', encoding='utf-8') as stream:
    stream.write(json.dumps(args) + '\n')
if (sdk / 'bootstrap-failure').exists():
    print('Detailed fake bootstrap failure: SDK dependencies unavailable.')
    raise SystemExit(17)
if not (sdk / 'ready').exists():
    print('Resolving cold SDK dependencies...')
    (sdk / 'ready').write_text('SDK cache initialized', encoding='utf-8')
if '--machine' in args:
    print((sdk / 'fake-version.json').read_text(encoding='utf-8'))
else:
    print('Flutter fake SDK is ready.')
    print('Benign SDK initialization diagnostic.', file=sys.stderr)
'''


class FlutterBootstrapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs cold SDK ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.pin = {'flutter_version': '1.2.3', 'flutter_revision': 'a' * 40}
        self.version = {'frameworkVersion': self.pin['flutter_version'],
                        'frameworkRevision': self.pin['flutter_revision']}
        self.put('scripts/toolchain.json', self.pin)
        self.put('scripts/analysis_targets.json', {'schema': 1, 'focused': ['lib/modern']})
        self.put('upstream/lib/modern/journal.dart', 'source remains untouched')
        self.put('BUILD_INFO.json', {'source_commit': 'b' * 40})
        self.sdk = self.root / '.tools/flutter'
        self.shim = self.put('.tools/flutter/bin/fake_flutter.py', FAKE_TOOL)
        self.put('.tools/flutter/fake-version.json', self.version)
        self.put('.tools/flutter/bin/flutter', 'host-independent SDK launcher fixture')
        suffix = '.bat' if os.name == 'nt' else ''
        self.put(f'.tools/flutter/bin/dart{suffix}', 'Dart launcher fixture')
        self.put('.tools/flutter/bin/flutter.bat',
                 f'@echo off\n"{sys.executable}" "{self.shim}" %*\nexit /b %ERRORLEVEL%\n')
        shutil.copyfile(SCRIPTS / 'common.ps1', self.root / 'scripts/common.ps1')

    def put(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, dict) else value, encoding='utf-8')
        return path

    def query(self, command, **kwargs):
        # Execute the fake SDK in a real child process, including when testing
        # the Linux entrypoint from Windows. No installed SDK is invoked.
        self.assertIn(Path(command[0]).name, ('flutter', 'flutter.bat'))
        return CHECK_OUTPUT([sys.executable, str(self.shim), *command[1:]], **kwargs)

    def calls(self):
        return [json.loads(line) for line in (self.sdk / 'calls.jsonl').read_text().splitlines()]

    def assert_bootstrapped(self):
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertIn('--version', calls[0])
        self.assertNotIn('--machine', calls[0])
        self.assertIn('--version', calls[1])
        self.assertIn('--machine', calls[1])

    def cached_mcp_fixture(self, source):
        web = self.root / '.local/dev-mcp/web'
        for name in ('index.html', 'main.dart.js', 'sw.js'):
            self.put(f'.local/dev-mcp/web/{name}', name)
        info = {'schema': 1, 'status': 'ready', 'devtools': True, 'source': source,
                'web_root': str(web), 'build_id': f'{source["commit"][:8]}-{source["inputs_sha256"][:8]}',
                'toolchain': self.pin,
                'main_js_sha256': digest(web / 'main.dart.js'), 'payload_hashes': file_hashes(web)}
        self.put('.local/dev-mcp/build.json', info)
        return web, info

    def test_mcp_cold_sdk_reuses_verified_cache_without_leaking_stdout(self):
        source = {'commit': 'b' * 40, 'inputs_sha256': 'c' * 64}
        _, info = self.cached_mcp_fixture(source)
        output = io.StringIO()
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'install_dependencies') as install, \
                patch.object(prepare, 'source_identity', return_value=source), \
                patch.object(prepare, 'run') as game_commands, \
                patch.object(prepare.subprocess, 'check_output', side_effect=self.query), \
                redirect_stdout(output):
            self.assertEqual(prepare.prepare(Namespace(out='.local/dev-mcp', rebuild=False)),
                             {**info, 'checked_source': source})
        self.assert_bootstrapped()
        install.assert_called_once()
        game_commands.assert_not_called()
        self.assertEqual(output.getvalue().strip(), 'Reusing verified development build bbbbbbbb-cccccccc; inputs match checkout bbbbbbbb.')

    def test_mcp_commit_only_reuse_returns_current_check_without_rewriting_artifact(self):
        compiled = {'commit': 'b' * 40, 'inputs_sha256': 'c' * 64}
        current = {**compiled, 'commit': 'd' * 40}
        web, info = self.cached_mcp_fixture(compiled)
        before = (web.parent / 'build.json').read_bytes()
        output = io.StringIO()
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'install_dependencies'), \
                patch.object(prepare, 'source_identity', return_value=current), \
                patch.object(prepare, 'run') as commands, \
                patch.object(prepare.subprocess, 'check_output', side_effect=self.query), redirect_stdout(output):
            self.assertEqual(prepare.prepare(Namespace(out='.local/dev-mcp', rebuild=False)),
                             {**info, 'checked_source': current})
        commands.assert_not_called()
        self.assertIn('build bbbbbbbb-cccccccc; inputs match checkout dddddddd', output.getvalue())
        self.assertEqual((web.parent / 'build.json').read_bytes(), before)
        self.assertEqual(file_hashes(web), info['payload_hashes'])

    def test_mcp_forced_rebuild_generates_current_identity_and_keeps_check_out_of_manifest(self):
        compiled = {'commit': 'b' * 40, 'inputs_sha256': 'c' * 64}
        current = {**compiled, 'commit': 'd' * 40}
        web, _ = self.cached_mcp_fixture(compiled)
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'install_dependencies'), \
                patch.object(prepare, 'source_identity', return_value=current), \
                patch.object(prepare, 'run') as commands, \
                patch.object(prepare.subprocess, 'check_output', side_effect=self.query):
            result = prepare.prepare(Namespace(out='.local/dev-mcp', rebuild=True))
        self.assertEqual(commands.call_count, 4)
        self.assertEqual(commands.call_args_list[0].args[0][1:], ['pub', 'get'])
        self.assertEqual(commands.call_args_list[1].args[0][1:], ['run', 'build_runner', 'build'])
        self.assertIn('--dart-define=LCS_BUILD=dddddddd-cccccccc', commands.call_args_list[2].args[0])
        manifest = json.loads((web.parent / 'build.json').read_text())
        self.assertEqual(manifest['source'], current)
        self.assertEqual(manifest['build_id'], 'dddddddd-cccccccc')
        self.assertNotIn('checked_source', manifest)
        self.assertEqual(result, {**manifest, 'checked_source': current})

    def test_mcp_wrong_pin_stops_before_package_installation_or_game_commands(self):
        self.put('.tools/flutter/fake-version.json', {**self.version, 'frameworkRevision': 'wrong'})
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'install_dependencies') as install, \
                patch.object(prepare, 'source_identity') as source, \
                patch.object(prepare, 'run') as game_commands, \
                patch.object(prepare.subprocess, 'check_output', side_effect=self.query):
            with self.assertRaisesRegex(ValueError, 'Flutter SDK does not match'):
                prepare.prepare(Namespace(out='.local/dev-mcp', rebuild=False))
        self.assert_bootstrapped()
        install.assert_not_called()
        source.assert_not_called()
        game_commands.assert_not_called()
        self.assertFalse((self.root / '.local/dev-mcp/build.json').exists())

    def test_mcp_bootstrap_failure_keeps_diagnostics_and_stops_before_machine_query(self):
        self.put('.tools/flutter/bootstrap-failure', 'fail the SDK initialization')
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(prepare, 'install_dependencies') as install, \
                patch.object(prepare, 'run') as game_commands, \
                patch.object(prepare.subprocess, 'check_output', side_effect=self.query):
            with self.assertRaises((ValueError, subprocess.CalledProcessError)) as failure:
                prepare.prepare(Namespace(out='.local/dev-mcp', rebuild=False))
        self.assertIn('Detailed fake bootstrap failure', str(failure.exception))
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn('--machine', self.calls()[0])
        install.assert_not_called()
        game_commands.assert_not_called()

    def test_linux_source_zip_cold_sdk_reaches_pin_check_before_project_mutation(self):
        self.put('.tools/flutter/fake-version.json', {**self.version, 'frameworkVersion': 'wrong'})
        original = (self.root / 'upstream/lib/modern/journal.dart').read_bytes()
        with patch.object(build_linux.platform, 'system', return_value='Linux'), \
                patch.object(build_linux.platform, 'machine', return_value='x86_64'), \
                patch.object(build_linux.subprocess, 'check_output', side_effect=self.query):
            with self.assertRaisesRegex(ValueError, 'Flutter SDK does not match'):
                build_linux.build(self.root)
        self.assert_bootstrapped()
        self.assertFalse((self.root / '.git').exists(), 'This is an extracted Source ZIP fixture.')
        self.assertFalse((self.root / '.local').exists())
        self.assertEqual((self.root / 'upstream/lib/modern/journal.dart').read_bytes(), original)

    def test_linux_bootstrap_failure_keeps_diagnostics_and_stops_before_machine_query(self):
        self.put('.tools/flutter/bootstrap-failure', 'fail the SDK initialization')
        with patch.object(build_linux.platform, 'system', return_value='Linux'), \
                patch.object(build_linux.platform, 'machine', return_value='x86_64'), \
                patch.object(build_linux.subprocess, 'check_output', side_effect=self.query):
            with self.assertRaises((ValueError, subprocess.CalledProcessError)) as failure:
                build_linux.build(self.root)
        self.assertIn('Detailed fake bootstrap failure', str(failure.exception))
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn('--machine', self.calls()[0])
        self.assertFalse((self.root / '.local').exists())

    def powershell(self):
        executable = shutil.which('powershell.exe')
        if os.name != 'nt' or not executable:
            self.skipTest('Windows PowerShell is required for the Windows SDK launcher.')
        def quoted(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = self.put('invoke-common.ps1',
                          "$ErrorActionPreference = 'Stop'\n"
                          f'. {quoted(self.root / "scripts/common.ps1")}\n'
                          f'if ((Get-LcsSourceCommit) -ne {quoted("b" * 40)}) {{ throw "Source ZIP identity lost." }}\n'
                          '$flutter = Get-LcsFlutter\n'
                          'if ($ErrorActionPreference -ne "Stop") { throw "Caller error preference changed." }\n'
                          'Write-Output $flutter\n')
        return subprocess.run([executable, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script)],
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)

    def test_powershell_cold_sdk_returns_only_path_and_preserves_source_zip_identity(self):
        result = self.powershell()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.sdk / 'bin/flutter.bat'))
        self.assertEqual(result.stderr, '')
        self.assert_bootstrapped()

    def test_powershell_wrong_pin_is_still_rejected_after_bootstrap(self):
        self.put('.tools/flutter/fake-version.json', {**self.version, 'frameworkRevision': 'wrong'})
        result = self.powershell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Flutter pin mismatch', result.stdout + result.stderr)
        self.assert_bootstrapped()

    def test_powershell_bootstrap_failure_keeps_native_diagnostics(self):
        self.put('.tools/flutter/bootstrap-failure', 'fail the SDK initialization')
        result = self.powershell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Detailed fake bootstrap failure', result.stdout + result.stderr)
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn('--machine', self.calls()[0])


if __name__ == '__main__':
    unittest.main()
