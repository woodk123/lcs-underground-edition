"""Check nightly change detection, release isolation and fresh-build packaging."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import nightly_release as release
import package_release as packaging
from release_common import file_hashes, verify_package


def put(root: Path, name: str, content: str = 'fixture') -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


def nightly(value: str = 'a' * 64, **extra) -> dict:
    return {'name': 'Nightly', 'prerelease': True, 'tag_name': 'nightly-123-1',
            'body': f'{release.MARKER}{value} -->', 'draft': False,
            'published_at': '2026-10-15T00:00:00Z', **extra}


class NightlyTests(unittest.TestCase):
    def test_change_detection_uses_only_published_managed_nightlies(self):
        value = 'a' * 64
        preview = nightly(tag_name='underground-preview-2026.10.15')
        draft = nightly(draft=True, published_at=None)
        self.assertIsNone(release.latest_successful([preview, draft]))
        self.assertTrue(release.changed_since(None, value))
        current = release.latest_successful([preview, draft, nightly()])
        self.assertFalse(release.changed_since(current, value))
        self.assertTrue(release.changed_since(current, 'b' * 64))

    def test_failed_upload_never_publishes_or_deletes_previous_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            assets = []
            for target, suffix in ((target, suffix) for target in
                                   ('Source', 'Web-Player', 'Windows-x64-Player', 'Linux-x64-Player')
                                   for suffix in ('', '.sha256')):
                name = f'LCS-Underground-Edition-nightly-456-1-{target}.zip{suffix}'
                put(output, name)
                assets.append({'name': name, 'sha256': packaging.digest(output / name)})
            put(output, 'release.json', json.dumps({'tag': 'nightly-456-1', 'fingerprint': 'b' * 64,
                                                   'source_commit': 'c' * 40, 'assets': assets}))
            calls = []

            def fake_gh(*args):
                calls.append(args)
                if args[:2] == ('release', 'upload'):
                    raise subprocess.CalledProcessError(1, ['gh', *args])
                return ''

            with patch.dict(os.environ, NIGHTLY_TAG='nightly-456-1', NIGHTLY_FINGERPRINT='b' * 64, GITHUB_RUN_ID='456'), \
                    patch.object(release, 'git', return_value='c' * 40), \
                    patch.object(release, 'fingerprint', return_value='b' * 64), \
                    patch.object(release, 'releases', return_value=[nightly()]), \
                    patch.object(release, 'gh', side_effect=fake_gh):
                with self.assertRaises(subprocess.CalledProcessError):
                    release.publish('owner/repo', output)
            self.assertEqual([call[:2] for call in calls], [('release', 'create'), ('release', 'upload')])

    def test_missing_linux_assets_prevent_any_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            put(output, 'release.json', json.dumps({
                'tag': 'nightly-456-1', 'fingerprint': 'b' * 64, 'source_commit': 'c' * 40,
                'assets': [{'name': f'LCS-Underground-Edition-nightly-456-1-{target}.zip{suffix}',
                            'sha256': 'a' * 64}
                           for target in ('Source', 'Web-Player', 'Windows-x64-Player')
                           for suffix in ('', '.sha256')],
            }))
            with patch.dict(os.environ, NIGHTLY_TAG='nightly-456-1', NIGHTLY_FINGERPRINT='b' * 64), \
                    patch.object(release, 'git', return_value='c' * 40), \
                    patch.object(release, 'fingerprint', return_value='b' * 64), \
                    patch.object(release, 'gh') as github:
                with self.assertRaisesRegex(ValueError, 'Expected Windows, Linux'):
                    release.publish('owner/repo', output)
                github.assert_not_called()

    def test_publication_retires_only_managed_nightlies_after_publish(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            assets = []
            for target, suffix in ((target, suffix) for target in
                                   ('Source', 'Web-Player', 'Windows-x64-Player', 'Linux-x64-Player')
                                   for suffix in ('', '.sha256')):
                name = f'LCS-Underground-Edition-nightly-456-1-{target}.zip{suffix}'
                put(output, name)
                assets.append({'name': name, 'sha256': packaging.digest(output / name)})
            put(output, 'release.json', json.dumps({'tag': 'nightly-456-1', 'fingerprint': 'b' * 64,
                                                   'source_commit': 'c' * 40, 'assets': assets}))
            calls = []

            def fake_gh(*args):
                calls.append(args)
                if args[:2] == ('release', 'view'):
                    return json.dumps({'assets': [{'name': item['name'], 'size': 7} for item in assets]})
                if args[0] == 'api':
                    return json.dumps(nightly('b' * 64, tag_name='nightly-456-1', html_url='https://example.com/nightly'))
                return ''

            with patch.dict(os.environ, NIGHTLY_TAG='nightly-456-1', NIGHTLY_FINGERPRINT='b' * 64,
                            GITHUB_RUN_ID='456', GITHUB_STEP_SUMMARY=str(output / 'summary')), \
                    patch.object(release, 'git', return_value='c' * 40), \
                    patch.object(release, 'fingerprint', return_value='b' * 64), \
                    patch.object(release, 'releases', return_value=[nightly(), nightly(tag_name='underground-preview-2026.10.15')]), \
                    patch.object(release, 'gh', side_effect=fake_gh):
                release.publish('owner/repo', output)
            deletes = [call for call in calls if call[:2] == ('release', 'delete')]
            self.assertEqual([call[2] for call in deletes], ['nightly-123-1'])
            self.assertLess(next(i for i, call in enumerate(calls) if call[:2] == ('release', 'edit')),
                            next(i for i, call in enumerate(calls) if call[:2] == ('release', 'delete')))

    def test_package_includes_exact_source_runtimes_licenses_and_checksums(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'checkout'
            root.mkdir()
            for name in ('LICENSE', 'AUTHORS.md', 'Play.cmd', 'README.md', '.gitignore',
                         'scripts/toolchain.json', 'docs/BUILDING.md', '.github/workflows/nightly.yml',
                         'upstream/lib/main.dart', 'upstream/lib/model.g.dart', 'upstream/pubspec.lock',
                         'upstream/pubspec.yaml', '.tools/flutter/LICENSE', 'upstream/fonts/journal/OFL.txt',
                         'upstream/fonts/modern/roboto_license.txt',
                         *(f'scripts/{name}' for name in packaging.WEB_SCRIPTS)):
                put(root, name)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            put(root, '.gitignore', '.tools/\n.local/\nrelease/\nupstream/build/\nvc/\n')
            subprocess.run(['git', '-C', str(root), 'add', '.'], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                            'commit', '-qm', 'fixture'], check=True, capture_output=True)
            revision = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'],
                                      check=True, capture_output=True, text=True).stdout.strip()
            web = root / 'upstream/build/web'
            native = root / 'upstream/build/windows/x64/runner/Release'
            for name in ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'):
                put(web, name)
            for name in ('lcs_new_age.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat',
                         'data/flutter_assets/NOTICES.Z', 'plugin.dll'):
                put(native, name)
            runtime = root / 'vc'
            for name in ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'):
                put(runtime, name)
            report = root / '.local/reports/build'
            steps = ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                     '05-full-analysis', '06-web-release', '07-offline-manifest', '08-windows-release']
            info = {'status': 'automated_checks_passed_manual_qa_pending', 'source_commit': revision,
                    'toolchain': {}, 'steps': [{'name': name, 'exit_code': 0} for name in steps]}
            put(report, 'build-info.json', json.dumps(info))
            linux = root / '.local/linux'
            for name in ('lcs_new_age', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so',
                         'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z'):
                put(linux / 'bundle', name)
            put(linux, 'evidence/build-info.json', json.dumps({
                'status': 'passed', 'source_commit': revision, 'toolchain': {},
                'steps': [{'name': name, 'exit_code': 0} for name in
                          ('dependencies', 'serialization', 'tests', 'focused-analysis', 'full-analysis', 'linux-release')],
                'bundle_hashes': file_hashes(linux / 'bundle'),
            }))
            output = root / 'release/nightly'
            result = packaging.package(root, report, runtime, output, 'nightly-123-1', 'b' * 64, 'owner/repo', linux=linux)
            self.assertEqual(len(result['assets']), 8)
            for directory in output.iterdir():
                if directory.is_dir():
                    self.assertEqual(verify_package(directory)['status'], 'passed')
            source = output / 'LCS-Underground-Edition-nightly-123-1-Source'
            self.assertEqual((source / 'upstream/lib/model.g.dart').read_bytes(), (root / 'upstream/lib/model.g.dart').read_bytes())
            self.assertTrue((source / '.github/workflows/nightly.yml').is_file())
            self.assertFalse((source / 'upstream/build').exists())
            player = output / 'LCS-Underground-Edition-nightly-123-1-Windows-x64-Player'
            self.assertEqual((player / 'plugin.dll').read_bytes(), (native / 'plugin.dll').read_bytes())
            self.assertIn('nightly-123-1-Source.zip', (player / 'SOURCE_REFERENCE.md').read_text(encoding='utf-8'))
            self.assertIn('https://github.com/owner/repo/releases/download/nightly-123-1/',
                          (player / 'SOURCE_REFERENCE.md').read_text(encoding='utf-8'))
            info['steps'][-1]['exit_code'] = 1
            put(report, 'build-info.json', json.dumps(info))
            with self.assertRaisesRegex(ValueError, 'Both builds'):
                packaging.package(root, report, runtime, root / 'release/failed', 'nightly-124-1', 'b' * 64, 'owner/repo')

    def test_fingerprint_ignores_docs_and_detects_game_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            put(root, 'upstream/lib/main.dart')
            put(root, 'docs/BUILDING.md')
            subprocess.run(['git', 'init', '-q', str(root)], check=True)

            def commit():
                subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
                subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                                'commit', '-qm', 'fixture'], check=True)

            def local_git(*args):
                return subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True, text=True).stdout.strip()

            commit()
            with patch.object(release, 'git', side_effect=local_git):
                first = release.fingerprint()
                put(root, 'docs/BUILDING.md', 'changed documentation')
                commit()
                self.assertEqual(first, release.fingerprint())
                put(root, 'upstream/lib/main.dart', 'changed code')
                commit()
                self.assertNotEqual(first, release.fingerprint())
                game_fingerprint = release.fingerprint()
                put(root, '.gitattributes', '/upstream/fonts/journal/OFL.txt text eol=lf\n')
                commit()
                self.assertNotEqual(game_fingerprint, release.fingerprint())


if __name__ == '__main__':
    unittest.main()
