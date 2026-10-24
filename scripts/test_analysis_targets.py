"""Every strict analyzer must use the shared scope, including standalone source rebuilds."""
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
import zipfile

import analysis_targets
import build_linux
import ci_worker
import package_release


SCRIPTS = Path(__file__).resolve().parent


class AnalysisTargetTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs analysis paths ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.targets = ['lib/modern', 'lib/devtools', 'lib/custom analyzer.dart']
        self.configuration = {'schema': 1, 'focused': self.targets}
        self.put('scripts/analysis_targets.json', self.configuration)
        for name in ('upstream/lib/modern/journal.dart', 'upstream/lib/devtools/bridge.dart',
                     'upstream/lib/custom analyzer.dart', 'upstream/lib/model.g.dart'):
            self.put(name)
        self.pin = {'flutter_version': '1.2.3', 'flutter_revision': 'a' * 40}
        self.put('scripts/toolchain.json', self.pin)
        self.version = json.dumps({'frameworkVersion': self.pin['flutter_version'],
                                   'frameworkRevision': self.pin['flutter_revision']})
        self.commit = 'b' * 40
        self.put('BUILD_INFO.json', {'source_commit': self.commit})
        self.commands = []

    def put(self, name, value='fixture'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, (dict, list)) else value, encoding='utf-8')
        return path

    def copy_helpers(self):
        for name in ('analysis_targets.py', 'release_common.py'):
            shutil.copyfile(SCRIPTS / name, self.root / 'scripts' / name)

    def process(self, command, **kwargs):
        self.commands.append((command, kwargs))
        class Process:
            stdout = ()
            def wait(self):
                return 0
        return Process()

    def test_current_scope_includes_development_bridge_and_is_portable(self):
        current = analysis_targets.focused_targets(SCRIPTS.parent)
        self.assertIn('lib/devtools', current)
        self.assertEqual(analysis_targets.focused_targets(self.root), self.targets)
        self.copy_helpers()
        result = subprocess.run([sys.executable, str(self.root / 'scripts/analysis_targets.py'),
                                 '--root', str(self.root)], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), self.targets)

    def test_invalid_missing_duplicate_or_non_source_targets_fail(self):
        self.put('upstream/lib/data.json')
        configurations = [[], {'schema': 2, 'focused': self.targets}, {'schema': True, 'focused': self.targets}, {'schema': 1},
                          {'schema': 1, 'focused': []}, {'schema': 1, 'focused': 'lib/modern'}]
        configurations += [{'schema': 1, 'focused': values} for values in (
            [None], ['lib/modern', 'lib/Modern'], ['/lib/modern'], ['C:/lib/modern'],
            ['../upstream/lib/modern'], ['lib//modern'], ['lib/../lib/modern'],
            ['lib\\modern'], ['test'], ['lib/missing.dart'], ['lib/data.json'])]
        for configuration in configurations:
            with self.subTest(configuration=configuration):
                self.put('scripts/analysis_targets.json', configuration)
                with self.assertRaises(ValueError):
                    analysis_targets.focused_targets(self.root)
        path = self.put('scripts/analysis_targets.json', 'interrupted JSON')
        with self.assertRaises(ValueError):
            analysis_targets.focused_targets(self.root)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            analysis_targets.focused_targets(self.root)

    def test_symlink_target_cannot_escape_source_tree(self):
        outside = self.root / 'outside'
        outside.mkdir()
        link = self.root / 'upstream/lib/external'
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest('Creating a symlink is not permitted on this host.')
        self.put('scripts/analysis_targets.json', {'schema': 1, 'focused': ['lib/external']})
        with self.assertRaisesRegex(ValueError, 'escapes upstream/lib'):
            analysis_targets.focused_targets(self.root)

    def test_ci_executes_strict_shared_scope_and_keeps_evidence_step_contract(self):
        with patch.object(ci_worker.platform, 'system', return_value='Linux'), \
                patch.object(ci_worker, 'identity', return_value={'source_commit': self.commit, 'toolchain': self.pin}), \
                patch.object(ci_worker, 'test_files', return_value=['test/focused_test.dart']), \
                patch.object(ci_worker.subprocess, 'check_output', return_value=self.version), \
                patch.object(ci_worker.subprocess, 'Popen', side_effect=self.process), \
                redirect_stdout(io.StringIO()):
            ci_worker.run_worker(self.root, 'checks', 'linux', 0)
        flutter = str(self.root / '.tools/flutter/bin/flutter')
        strict = [(command, kwargs) for command, kwargs in self.commands
                  if command[:3] == [flutter, 'analyze', '--no-pub'] and '--no-fatal-warnings' not in command]
        self.assertEqual(len(strict), 1)
        self.assertEqual(strict[0][0], [flutter, 'analyze', '--no-pub', *self.targets])
        self.assertEqual(strict[0][1]['cwd'], self.root / 'upstream')
        report = json.loads((self.root / '.local/ci/checks-linux-0/report.json').read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertEqual([step['name'] for step in report['steps']],
                         ci_worker.required_steps('checks', 'linux', 0))

    def test_linux_source_rebuild_executes_strict_shared_scope(self):
        for name in ('lcs_new_age', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so',
                     'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z'):
            self.put('upstream/build/linux/x64/release/bundle/' + name)
        with patch.object(build_linux.platform, 'system', return_value='Linux'), \
                patch.object(build_linux.platform, 'machine', return_value='x86_64'), \
                patch.object(build_linux.subprocess, 'check_output', return_value=self.version), \
                patch.object(build_linux.subprocess, 'Popen', side_effect=self.process), \
                redirect_stdout(io.StringIO()):
            build_linux.build(self.root)
        flutter = str(self.root / '.tools/flutter/bin/flutter')
        self.assertIn([flutter, 'analyze', '--no-pub', *self.targets], [command for command, _ in self.commands])
        report = json.loads((self.root / '.local/linux/evidence/build-info.json').read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertEqual([step['name'] for step in report['steps']],
                         ['dependencies', 'serialization', 'tests', 'focused-analysis', 'full-analysis', 'linux-release'])

    def test_invalid_or_missing_configuration_stops_python_builders_before_commands(self):
        path = self.root / 'scripts/analysis_targets.json'
        for missing in (False, True):
            if missing:
                path.unlink()
            else:
                self.put('scripts/analysis_targets.json', {'schema': 1, 'focused': []})
            for builder in ('ci', 'linux'):
                with self.subTest(missing=missing, builder=builder), \
                        patch.object(build_linux.platform, 'system', return_value='Linux'), \
                        patch.object(build_linux.platform, 'machine', return_value='x86_64'), \
                        patch.object(build_linux.subprocess, 'check_output') as version, \
                        patch.object(build_linux.subprocess, 'Popen') as execute:
                    with self.assertRaises((OSError, ValueError)):
                        if builder == 'ci':
                            ci_worker.run_worker(self.root, 'checks', 'linux', 0)
                        else:
                            build_linux.build(self.root)
                    version.assert_not_called()
                    execute.assert_not_called()
                    self.assertFalse((self.root / '.local').exists())

    def prepare_powershell_builder(self):
        self.copy_helpers()
        shutil.copyfile(SCRIPTS / 'build_release.ps1', self.root / 'scripts/build_release.ps1')
        def quoted(value):
            return "'" + str(value).replace("'", "''") + "'"
        flutter = self.root / '.tools/flutter/bin/flutter.bat'
        self.put('scripts/common.ps1',
                 'Set-StrictMode -Version Latest\n'
                 f'function Get-LcsRoot {{ return {quoted(self.root)} }}\n'
                 f'function Get-LcsSourceCommit([string]$Root) {{ return {quoted(self.commit)} }}\n'
                 f'function Get-LcsFlutter {{ return {quoted(flutter)} }}\n'
                 f'function Get-LcsPython {{ return {quoted(sys.executable)} }}\n')
        trace = self.root / 'tool-calls.jsonl'
        recorder = self.put('scripts/record_tool.py',
                            'import json, sys\n'
                            f'with open({str(trace)!r}, "a", encoding="utf-8") as stream:\n'
                            '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n')
        for tool in ('flutter', 'dart'):
            self.put(f'.tools/flutter/bin/{tool}.bat',
                     f'@echo off\n"{sys.executable}" "{recorder}" {tool} %*\nexit /b %ERRORLEVEL%\n')
        self.put('scripts/package_release.py', recorder.read_text().replace('sys.argv[1:]', '["package", *sys.argv[1:]]'))
        return trace

    def run_powershell_builder(self):
        executable = shutil.which('powershell.exe')
        if not executable:
            self.skipTest('Windows PowerShell is unavailable.')
        return subprocess.run([executable, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                               str(self.root / 'scripts/build_release.ps1')], cwd=self.root,
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)

    @unittest.skipUnless(os.name == 'nt', 'The Windows release builder needs Windows PowerShell and batch tools.')
    def test_powershell_source_rebuild_executes_strict_shared_scope_with_spaces(self):
        trace = self.prepare_powershell_builder()
        result = self.run_powershell_builder()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = [json.loads(line) for line in trace.read_text().splitlines()]
        self.assertIn(['flutter', '--suppress-analytics', 'analyze', '--no-pub', *self.targets], commands)
        reports = list((self.root / '.local/reports').glob('*/build-info.json'))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text(encoding='utf-8-sig'))
        self.assertEqual(report['status'], 'automated_checks_and_packaging_passed_manual_qa_pending')
        self.assertEqual([step['name'] for step in report['steps']], [
            '01-dependencies', '02-serialization', '03-tests', '04-focused-analysis', '05-full-analysis',
            '06-web-release', '07-offline-manifest', '08-package'])

    @unittest.skipUnless(os.name == 'nt', 'The Windows release builder needs Windows PowerShell and batch tools.')
    def test_powershell_invalid_or_missing_configuration_stops_before_build_commands(self):
        trace = self.prepare_powershell_builder()
        path = self.root / 'scripts/analysis_targets.json'
        for missing in (False, True):
            with self.subTest(missing=missing):
                if missing:
                    path.unlink()
                else:
                    self.put('scripts/analysis_targets.json', {'schema': 1, 'focused': []})
                result = self.run_powershell_builder()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('analysis_targets', result.stdout + result.stderr)
                self.assertFalse(trace.exists())
                self.assertFalse((self.root / '.local').exists())

    def test_shared_configuration_and_loader_survive_source_zip_extraction(self):
        self.copy_helpers()
        for name in ('LICENSE', 'AUTHORS.md', 'README.md', '.gitignore', 'Play.cmd',
                     'scripts/common.ps1', 'scripts/launch.ps1', 'scripts/serve.py', 'scripts/stop.ps1',
                     'docs/BUILDING.md', '.tools/flutter/LICENSE', 'upstream/fonts/journal/OFL.txt',
                     'upstream/fonts/modern/roboto_license.txt'):
            self.put(name)
        for name in ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'):
            self.put('upstream/build/web/' + name)
        steps = ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                 '05-full-analysis', '06-web-release', '07-offline-manifest']
        report = self.put('.local/report/build-info.json', {
            'status': 'automated_checks_passed_manual_qa_pending', 'source_commit': self.commit,
            'toolchain': self.pin, 'steps': [{'name': name, 'exit_code': 0} for name in steps]}).parent
        output = self.root / 'release/analysis-test'
        package_release.package(self.root, report, None, output, 'analysis-test', None, 'owner/repo')
        source_name = 'LCS-Underground-Edition-analysis-test-Source'
        extracted = self.root / 'extracted'
        with zipfile.ZipFile(output / (source_name + '.zip')) as archive:
            archive.extractall(extracted)
        source = extracted / source_name
        self.assertFalse((source / '.git').exists())
        self.assertEqual(analysis_targets.focused_targets(source), self.targets)
        result = subprocess.run([sys.executable, str(source / 'scripts/analysis_targets.py')], cwd=source,
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), self.targets)


if __name__ == '__main__':
    unittest.main()
