"""Opt-in Windows plugin junctions preserve targets and refuse unsafe/conflicting setup."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent


@unittest.skipUnless(os.name == 'nt', 'Directory junction preparation is Windows-only.')
class WindowsPluginPreparationTests(unittest.TestCase):
    def setUp(self):
        self.powershell = shutil.which('powershell.exe')
        if not self.powershell:
            self.skipTest('Windows PowerShell is unavailable.')
        temporary = tempfile.TemporaryDirectory(prefix='lcs plugins [fixture] ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / 'scripts').mkdir()
        self.helper = self.root / 'scripts/prepare_windows_plugins.ps1'
        shutil.copyfile(SCRIPTS / self.helper.name, self.helper)
        self.put('scripts/toolchain.json', {'flutter_version': '3.47.7'})
        self.put('upstream/pubspec.yaml', 'name: fixture\n')
        for platform in ('windows', 'linux'):
            (self.root / 'upstream' / platform / 'flutter').mkdir(parents=True)
        self.one = self.root / 'cache with spaces; $(NotACommand)' / 'plugin one'
        self.two = self.root / 'cache with spaces; $(NotACommand)' / 'plugin two'
        for index, target in enumerate((self.one, self.two)):
            target.mkdir(parents=True)
            (target / 'data.bin').write_bytes(bytes([index, 37, 255, 0]))
        self.metadata = {'version': '3.47.7', 'plugins': {
            'windows': [{'name': 'plugin_one', 'path': str(self.one)},
                        {'name': 'plugin_two', 'path': str(self.two), 'native_build': False}],
            'linux': [{'name': 'plugin_one', 'path': str(self.one)}],
        }}
        self.save_metadata()
        self.targets_before = self.target_data()
        self.linker = self.put('scripts/fixture_junction.ps1',
                              'param([string]$Path, [string]$Target)\n'
                              "$ErrorActionPreference = 'Stop'\n"
                              '[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))\n'
                              'Push-Location -LiteralPath ([IO.Path]::GetDirectoryName($Path))\n'
                              'try { New-Item -ItemType Junction -Name ([IO.Path]::GetFileName($Path)) -Value ([WildcardPattern]::Escape($Target)) | Out-Null }\n'
                              'finally { Pop-Location }\n')

    def put(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, (dict, list)) else value, encoding='utf-8')
        return path

    def save_metadata(self):
        return self.put('upstream/.flutter-plugins-dependencies', self.metadata)

    def destination(self, platform, name='plugin_one'):
        return self.root / 'upstream' / platform / 'flutter/ephemeral/.plugin_symlinks' / name

    def run_helper(self):
        return subprocess.run([self.powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                               '-File', str(self.helper)], cwd=self.root.parent,
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)

    def junction(self, path, target):
        result = subprocess.run([self.powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                 '-File', str(self.linker), '-Path', str(path), '-Target', str(target)],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def target_data(self):
        cache = self.one.parent
        return {path.relative_to(cache): path.read_bytes() for path in cache.rglob('*') if path.is_file()}

    def assert_targets_preserved(self):
        self.assertEqual(self.target_data(), self.targets_before)

    def assert_no_generated_parents(self):
        for platform in ('windows', 'linux'):
            self.assertFalse(self.destination(platform).parent.exists())
        self.assert_targets_preserved()

    def test_creates_all_metadata_links_with_spaces_and_is_idempotent(self):
        before = (self.root / 'upstream/.flutter-plugins-dependencies').read_bytes()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(len(report['created']), 3)
        self.assertEqual(report['retained'], [])
        destinations = [self.destination('windows'), self.destination('windows', 'plugin_two'),
                        self.destination('linux')]
        for path, target in zip(destinations, (self.one, self.two, self.one)):
            self.assertTrue(path.is_junction())
            self.assertEqual(path.resolve(), target)
        identities = {path: path.lstat().st_ino for path in destinations}
        again = self.run_helper()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertEqual(json.loads(again.stdout)['created'], [])
        self.assertEqual(len(json.loads(again.stdout)['retained']), 3)
        self.assertEqual({path: path.lstat().st_ino for path in destinations}, identities)
        self.assertEqual((self.root / 'upstream/.flutter-plugins-dependencies').read_bytes(), before)
        self.assert_targets_preserved()

    def test_correct_existing_junction_is_preserved(self):
        path = self.destination('windows')
        self.junction(path, self.one)
        identity = path.lstat().st_ino
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['created']), 2)
        self.assertEqual(json.loads(result.stdout)['retained'], [str(path)])
        self.assertEqual(path.lstat().st_ino, identity)
        self.assert_targets_preserved()

    def test_invalid_names_and_duplicate_entries_fail_before_creation(self):
        for name in ('../escape', 'nested/name', 'nested\\name', 'con', 'MixedCase', 'x;$(Get-Item)'):
            with self.subTest(name=name):
                self.metadata['plugins']['linux'][0]['name'] = name
                self.save_metadata()
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Invalid or duplicate', result.stdout + result.stderr)
                self.assert_no_generated_parents()
        self.metadata['plugins']['linux'] = [{'name': 'plugin_one', 'path': str(self.one)}] * 2
        self.save_metadata()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stdout + result.stderr)
        self.assert_no_generated_parents()

    def test_malformed_metadata_and_wrong_sdk_version_make_no_links(self):
        variants = [[], {}, {'version': 'old', 'plugins': {}},
                    {'version': '3.47.7', 'plugins': []},
                    {'version': '3.47.7', 'plugins': {'windows': {}}},
                    {'version': '3.47.7', 'plugins': {'linux': [{'name': 3, 'path': str(self.one)}]}}]
        for value in variants:
            with self.subTest(metadata=value):
                self.put('upstream/.flutter-plugins-dependencies', value)
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assert_no_generated_parents()
        self.put('upstream/.flutter-plugins-dependencies', 'interrupted JSON')
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assert_no_generated_parents()
        self.save_metadata()
        self.put('scripts/toolchain.json', {'flutter_version': ['3.47.7']})
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assert_no_generated_parents()

    def test_missing_metadata_explains_the_pub_get_prerequisite(self):
        (self.root / 'upstream/.flutter-plugins-dependencies').unlink()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pub get first', result.stdout + result.stderr)
        self.assert_no_generated_parents()

    def test_missing_relative_unc_and_overlapping_targets_are_rejected(self):
        for target in (str(self.root / 'absent'), str(self.one / 'data.bin'), '../relative',
                       r'\\remote\share', 'C:relative', 'C:\\', str(self.root)):
            with self.subTest(target=target):
                self.metadata['plugins']['linux'][0]['path'] = target
                self.save_metadata()
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assert_no_generated_parents()

    def test_conflicting_file_or_directory_is_not_replaced(self):
        conflict = self.destination('windows', 'plugin_two')
        conflict.parent.mkdir(parents=True)
        for directory in (False, True):
            with self.subTest(directory=directory):
                if directory:
                    conflict.mkdir()
                else:
                    conflict.write_text('retain conflicting file')
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Conflicting plugin entry', result.stdout + result.stderr)
                self.assertFalse(self.destination('windows').exists(), 'Earlier valid entries must not be created.')
                self.assertFalse(self.destination('linux').exists())
                self.assert_targets_preserved()
                if directory:
                    conflict.rmdir()
                else:
                    self.assertEqual(conflict.read_text(), 'retain conflicting file')
                    conflict.unlink()

    def test_stale_link_is_refused_without_retargeting_or_touching_data(self):
        path = self.destination('windows', 'plugin_two')
        self.junction(path, self.one)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Stale plugin link target', result.stdout + result.stderr)
        self.assertEqual(path.resolve(), self.one)
        self.assertFalse(self.destination('windows').exists())
        self.assertFalse(self.destination('linux').exists())
        self.assert_targets_preserved()

    def test_unexpected_stale_entry_is_not_removed(self):
        stale = self.destination('windows', 'obsolete_plugin')
        self.junction(stale, self.one)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected stale plugin entry', result.stdout + result.stderr)
        self.assertEqual(stale.resolve(), self.one)
        self.assertFalse(self.destination('windows').exists())
        self.assert_targets_preserved()

    def test_broken_existing_link_is_detected_before_other_links_are_created(self):
        empty = self.root / 'empty old target'
        empty.mkdir()
        broken = self.destination('windows', 'plugin_two')
        self.junction(broken, empty)
        empty.rmdir()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.destination('windows').exists())
        self.assertFalse(self.destination('linux').exists())
        self.assertTrue(broken.is_junction())
        self.assert_targets_preserved()

    def test_parent_junction_escape_is_refused_without_writing_through_it(self):
        outside = self.root / 'outside plugin output'
        outside.mkdir()
        marker = outside / 'keep.txt'
        marker.write_text('retain outside data')
        parent = self.destination('windows').parent.parent
        self.junction(parent, outside)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ordinary checkout directory', result.stdout + result.stderr)
        self.assertEqual(list(outside.iterdir()), [marker])
        self.assertEqual(marker.read_text(), 'retain outside data')
        self.assertFalse(self.destination('linux').exists())
        self.assert_targets_preserved()


if __name__ == '__main__':
    unittest.main()
