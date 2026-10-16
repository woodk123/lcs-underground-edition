"""Release-integrity and standalone source-rebuild regression tests."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_release
from release_common import archive_package, digest, runtime_hashes, verify_package


def put(root, name, data='fixture'):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding='utf-8')
    return path


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_archive_survives_clean_extraction(self):
        package = self.root / 'Player'
        put(package, 'data/portrait.png', 'runtime artwork')
        put(package, 'LICENSE')
        result = archive_package(package)
        destination = self.root / 'extracted'
        destination.mkdir()
        archive = Path(result['archive'])
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(destination)
        for suffix in ('.zip', '.zip.sha256'):
            (destination / ('Player' + suffix)).write_bytes((self.root / ('Player' + suffix)).read_bytes())
        self.assertEqual(verify_package(destination / 'Player')['archive_sha256'], result['archive_sha256'])

    def test_modified_or_missing_file_is_rejected(self):
        package = self.root / 'Player'
        file = put(package, 'data/game', 'original')
        archive_package(package)
        file.write_text('changed')
        with self.assertRaisesRegex(ValueError, 'File hash mismatch'):
            verify_package(package)
        file.unlink()
        with self.assertRaisesRegex(ValueError, 'Manifest inventory'):
            verify_package(package)

    def test_unsafe_manifest_path_is_rejected(self):
        package = self.root / 'Player'
        put(package, 'FILES.sha256', 'a' * 64 + '  ../outside\n')
        with self.assertRaisesRegex(ValueError, 'Unsafe relative path'):
            verify_package(package)

    def test_replaced_zip_with_matching_sidecar_is_still_rejected(self):
        package = self.root / 'Player'
        put(package, 'data/game', 'original')
        archive_package(package)
        archive = self.root / 'Player.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('Player/data/game', 'changed inside ZIP')
            bundle.writestr('Player/FILES.sha256', (package / 'FILES.sha256').read_bytes())
        archive.with_name('Player.zip.sha256').write_text(f'{digest(archive)}  Player.zip\n')
        with self.assertRaisesRegex(ValueError, 'ZIP file hash mismatch'):
            verify_package(package)

    def test_missing_windows_runtime_is_rejected(self):
        put(self.root, 'lcs_new_age.exe')
        with self.assertRaisesRegex(ValueError, 'Required runtime'):
            runtime_hashes(self.root, 'windows-x64')

    def source_fixture(self):
        root = self.root / 'source-without-git'
        for name in ('LICENSE', 'AUTHORS.md', 'README.md', '.gitignore', 'Play.cmd',
                     'scripts/launch.ps1', 'scripts/stop.ps1', 'scripts/common.ps1', 'scripts/serve.py',
                     'upstream/lib/main.dart', 'upstream/lib/model.g.dart', 'upstream/pubspec.lock',
                     'upstream/pubspec.yaml', 'docs/BUILDING.md', '.tools/flutter/LICENSE',
                     'upstream/fonts/journal/OFL.txt', 'upstream/fonts/modern/roboto_license.txt'):
            put(root, name)
        web = root / 'upstream/build/web'
        for name in ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'):
            put(web, name)
        steps = ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                 '05-full-analysis', '06-web-release', '07-offline-manifest']
        info = {'status': 'automated_checks_passed_manual_qa_pending', 'source_commit': 'a' * 40,
                'toolchain': {}, 'steps': [{'name': name, 'exit_code': 0} for name in steps]}
        report = root / '.local/report'
        put(report, 'build-info.json', json.dumps(info))
        return root, report, info

    def test_web_player_and_complete_source_package_without_git(self):
        root, report, _ = self.source_fixture()
        output = root / 'release/local-test'
        result = package_release.package(root, report, None, output, 'local-test', None, 'owner/repo')
        self.assertEqual(len(result['assets']), 4)
        source = output / 'LCS-Underground-Edition-local-test-Source'
        player = output / 'LCS-Underground-Edition-local-test-Web-Player'
        self.assertEqual((source / 'upstream/lib/model.g.dart').read_bytes(), (root / 'upstream/lib/model.g.dart').read_bytes())
        self.assertFalse((source / '.tools').exists())
        self.assertFalse((source / 'upstream/build').exists())
        self.assertFalse((player / 'source').exists())
        self.assertTrue((source / 'SOURCE_INFO.md').is_file())
        self.assertIn('(../LCS-Underground-Edition-local-test-Source.zip)',
                      (player / 'SOURCE_REFERENCE.md').read_text())
        self.assertEqual(verify_package(player)['status'], 'passed')
        self.assertEqual(verify_package(source)['status'], 'passed')

    def test_named_preview_has_exact_absolute_source_link_and_identity(self):
        root, report, info = self.source_fixture()
        tag = 'underground-preview-2026.10.16'
        output = root / 'release' / tag
        result = package_release.package(root, report, None, output, tag, None, 'owner/repo', published=True)
        source_name = 'LCS-Underground-Edition-2026.10.16-Source.zip'
        player = output / 'LCS-Underground-Edition-2026.10.16-Web-Player'
        self.assertEqual([asset['name'] for asset in result['assets']], [
            source_name, source_name + '.sha256',
            player.name + '.zip', player.name + '.zip.sha256',
        ])
        reference = (player / 'SOURCE_REFERENCE.md').read_text(encoding='utf-8')
        self.assertIn(f'https://github.com/owner/repo/releases/download/{tag}/{source_name}', reference)
        self.assertIn(digest(output / source_name), reference)
        self.assertIn(info['source_commit'], reference)
        self.assertEqual(json.loads((player / 'BUILD_INFO.json').read_text())['release_tag'], tag)
        self.assertIsNone(result['fingerprint'])
        self.assertEqual(result['tag'], tag)
        self.assertEqual(verify_package(player)['status'], 'passed')

    def test_cli_explicit_tag_and_local_default_choose_correct_source_links(self):
        root, report, _ = self.source_fixture()
        base = ['package_release.py', '--root', str(root), '--report', str(report)]
        for extra, published in (([], False), (['--tag', 'preview-123', '--repository', 'owner/fork'], True)):
            with self.subTest(published=published), patch.object(sys, 'argv', base + extra), \
                    patch.object(package_release, 'package', return_value={}) as package, \
                    patch('builtins.print'):
                package_release.main()
            self.assertEqual(package.call_args.kwargs['published'], published)
            if published:
                self.assertEqual(package.call_args.args[4], 'preview-123')
                self.assertEqual(package.call_args.args[6], 'owner/fork')
            else:
                self.assertTrue(package.call_args.args[4].startswith('local-'))

    def test_cli_cannot_mix_manual_tag_with_nightly(self):
        with patch.object(sys, 'argv', ['package_release.py', '--root', '.', '--report', '.',
                                      '--tag', 'preview', '--nightly']), patch.object(sys, 'stderr'), \
                self.assertRaises(SystemExit) as result:
            package_release.main()
        self.assertEqual(result.exception.code, 2)

    def git_source_fixture(self):
        root, report, info = self.source_fixture()
        put(root, '.gitignore', '.tools/\n.local/\nrelease/\nupstream/build/\n')
        subprocess.run(['git', 'init', '-q', str(root)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True, capture_output=True)
        self.git_commit(root)
        info['source_commit'] = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'],
                                              check=True, capture_output=True, text=True).stdout.strip()
        put(report, 'build-info.json', json.dumps(info))
        return root, report, info

    @staticmethod
    def git_commit(root):
        subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-qm', 'fixture'], check=True, capture_output=True)

    def test_clean_git_checkout_with_ignored_outputs_packages(self):
        root, report, _ = self.git_source_fixture()
        result = package_release.package(root, report, None, root / 'release/clean', 'clean', None, 'owner/repo')
        self.assertEqual(len(result['assets']), 4)

    def test_git_source_modified_or_untracked_after_build_is_rejected(self):
        for name in ('upstream/lib/main.dart', 'upstream/lib/new.dart'):
            with self.subTest(name=name):
                # Each fixture gets its own checkout, preserving the previous failed output for inspection.
                with tempfile.TemporaryDirectory() as temporary:
                    previous_root = self.root
                    self.root = Path(temporary)
                    try:
                        root, report, _ = self.git_source_fixture()
                    finally:
                        self.root = previous_root
                    put(root, name, 'source changed since build')
                    output = root / 'release/dirty'
                    with self.assertRaisesRegex(ValueError, 'clean Git checkout'):
                        package_release.package(root, report, None, output, 'dirty', None, 'owner/repo')
                    self.assertFalse(output.exists())

    def test_git_head_changed_since_build_is_rejected(self):
        root, report, _ = self.git_source_fixture()
        put(root, 'README.md', 'new committed source')
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True, capture_output=True)
        self.git_commit(root)
        output = root / 'release/stale'
        with self.assertRaisesRegex(ValueError, 'source commit changed'):
            package_release.package(root, report, None, output, 'stale', None, 'owner/repo')
        self.assertFalse(output.exists())

    @unittest.skipUnless(shutil.which('powershell') or shutil.which('pwsh'), 'PowerShell is required')
    def test_builder_rejects_dirty_source_before_querying_flutter(self):
        root, _, _ = self.git_source_fixture()
        scripts = Path(__file__).resolve().parent
        for name in ('build_release.ps1', 'common.ps1'):
            shutil.copyfile(scripts / name, root / 'scripts' / name)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True, capture_output=True)
        self.git_commit(root)
        put(root, 'upstream/lib/main.dart', 'uncommitted change')
        result = subprocess.run([shutil.which('powershell') or shutil.which('pwsh'), '-NoProfile',
                                 '-ExecutionPolicy', 'Bypass', '-File', str(root / 'scripts/build_release.ps1')],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('clean Git checkout', result.stdout + result.stderr)
        self.assertNotIn('Pinned Flutter SDK missing', result.stdout + result.stderr)

    def test_invalid_published_tag_or_repository_is_rejected_before_packaging(self):
        root, report, _ = self.source_fixture()
        for tag, repository in (('../preview', 'owner/repo'), ('preview', 'owner/repo/extra')):
            with self.subTest(tag=tag, repository=repository), self.assertRaisesRegex(ValueError, 'Invalid'):
                package_release.package(root, report, None, root / 'release/invalid',
                                        tag, None, repository, published=True)
        self.assertFalse((root / 'release/invalid').exists())

    def test_failed_build_and_existing_output_are_rejected(self):
        root, report, info = self.source_fixture()
        info['steps'][2]['exit_code'] = 1
        put(report, 'build-info.json', json.dumps(info))
        output = root / 'release/local-test'
        with self.assertRaisesRegex(ValueError, 'all checks'):
            package_release.package(root, report, None, output, 'local-test', None, 'owner/repo')
        self.assertFalse(output.exists())
        info['steps'][2]['exit_code'] = 0
        put(report, 'build-info.json', json.dumps(info))
        output.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'fresh release output'):
            package_release.package(root, report, None, output, 'local-test', None, 'owner/repo')


if __name__ == '__main__':
    unittest.main()
