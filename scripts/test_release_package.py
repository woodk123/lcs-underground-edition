"""Release-integrity and standalone source-rebuild regression tests."""
import json
from pathlib import Path
import tempfile
import unittest
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
        self.assertIn('Source.zip', (player / 'SOURCE_REFERENCE.md').read_text())
        self.assertEqual(verify_package(player)['status'], 'passed')
        self.assertEqual(verify_package(source)['status'], 'passed')

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
