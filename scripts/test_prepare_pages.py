"""Pages preparation preserves nightly payloads and rejects untrusted archives."""
import json
import shutil
from pathlib import Path
import tempfile
import unittest
import zipfile

import prepare_pages
from release_common import archive_package, digest


def put(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


class PreparePagesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.downloads = self.root / 'downloads'
        self.downloads.mkdir()
        self.tag = 'nightly-123-1'
        prefix = f'LCS-Underground-Edition-{self.tag}'
        self.source = self.downloads / f'{prefix}-Source'
        self.player = self.downloads / f'{prefix}-Web-Player'
        self.output = self.root / 'site'
        common = {'release_tag': self.tag, 'runtime_source_commit': 'abc',
                  'packaging_commit': 'abc', 'source_commit': 'abc', 'fingerprint': '123'}
        put(self.source, 'BUILD_INFO.json', json.dumps({**common, 'target': 'corresponding-source'}))
        put(self.source, 'upstream/main.dart', 'matching modified source')
        source_info = archive_package(self.source)
        self.info = {**common, 'target': 'web', 'source_archive': self.source.name + '.zip',
                     'source_archive_sha256': source_info['archive_sha256']}
        put(self.player, 'BUILD_INFO.json', json.dumps(self.info))
        for name in ('LICENSE', 'AUTHORS.md', 'SOURCE_REFERENCE.md', 'README.md',
                     'licenses/Flutter-LICENSE.txt', 'licenses/LibreBaskerville-OFL.txt',
                     'licenses/Roboto-LICENSE.txt', 'Play.cmd', 'scripts/serve.py'):
            put(self.player, name, name)
        for name, value in {'index.html': '<html><base href="/"><body><div class="bar"></div></body></html>',
                            'main.dart.js': 'compiled() // immutable',
                            'flutter_bootstrap.js': 'bootstrap()', 'assets/example.bin': 'asset'}.items():
            put(self.player, 'web/' + name, value)
        self.resources = {p.relative_to(self.player / 'web').as_posix(): prepare_pages.crc(p.read_bytes())
                          for p in (self.player / 'web').rglob('*') if p.is_file()}
        manifest = prepare_pages.manifest_json(self.resources)
        put(self.player, 'web/sw.js', f'const RESOURCES = {manifest};\n'
            f"const VERSION = '{prepare_pages.crc(manifest.encode())}';\n// worker logic\n")
        archive_package(self.player)

    def run_prepare(self):
        return prepare_pages.prepare(self.downloads, self.output, '/lcs-underground-edition/', self.tag)

    def test_hosted_base_manifest_source_and_immutable_payload(self):
        web_archive = self.player.with_suffix('.zip')
        source_archive = self.source.with_suffix('.zip')
        original_zip_hash = digest(web_archive)
        original_source_hash = digest(source_archive)
        result = self.run_prepare()
        index = (self.output / 'index.html').read_text()
        self.assertIn('<base href="/lcs-underground-edition/">', index)
        self.assertIn('href="source.html"', index)
        self.assertIn(source_archive.name, (self.output / 'source.html').read_text())
        self.assertEqual(digest(web_archive), original_zip_hash)
        self.assertEqual(digest(self.output / source_archive.name), original_source_hash)
        self.assertEqual((self.output / 'main.dart.js').read_bytes(),
                         (self.player / 'web/main.dart.js').read_bytes())
        worker, resources = prepare_pages.read_manifest(self.output)
        self.assertNotEqual(resources['index.html'], self.resources['index.html'])
        self.assertEqual({k: v for k, v in resources.items() if k != 'index.html'},
                         {k: v for k, v in self.resources.items() if k != 'index.html'})
        self.assertNotIn(source_archive.name, resources)
        self.assertNotIn('Play.cmd', [p.name for p in self.output.iterdir()])
        self.assertFalse((self.output / 'scripts').exists())
        self.assertTrue((self.output / '.nojekyll').exists())
        self.assertIn(result['service_worker_version'], worker)
        self.assertEqual((self.output / 'LICENSE').read_bytes(), (self.player / 'LICENSE').read_bytes())

    def test_numbered_release_preserves_payload_with_no_nightly_fingerprint(self):
        tag = 'underground-v0.1.0'
        prefix = f'LCS-Underground-Edition-{tag}'
        source = self.downloads / f'{prefix}-Source'
        player = self.downloads / f'{prefix}-Web-Player'
        shutil.copytree(self.source, source)
        shutil.copytree(self.player, player)
        for folder in (source, player):
            (folder / 'FILES.sha256').unlink()
        source_info = json.loads((source / 'BUILD_INFO.json').read_text())
        source_info.update(release_tag=tag, fingerprint=None)
        put(source, 'BUILD_INFO.json', json.dumps(source_info))
        result = archive_package(source)
        info = {**self.info, 'release_tag': tag, 'fingerprint': None,
                'source_archive': source.name + '.zip', 'source_archive_sha256': result['archive_sha256']}
        put(player, 'BUILD_INFO.json', json.dumps(info))
        archive_package(player)
        prepared = prepare_pages.prepare(self.downloads, self.output, '/lcs-underground-edition/', tag)
        self.assertEqual(prepared['tag'], tag)
        self.assertIn(f'Release build: <code>{tag}</code>', (self.output / 'source.html').read_text())
        self.assertEqual(digest(self.output / 'main.dart.js'), digest(player / 'web/main.dart.js'))
        self.assertEqual(digest(self.output / (source.name + '.zip')), result['archive_sha256'])
        prepare_pages.read_manifest(self.output)

    def test_bad_archive_checksum(self):
        with self.player.with_suffix('.zip').open('ab') as archive:
            archive.write(b'changed')
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.run_prepare()
        self.assertFalse(self.output.exists())

    def test_embedded_file_hash_mismatch(self):
        archive = self.player.with_suffix('.zip')
        with zipfile.ZipFile(archive) as original:
            files = {name: original.read(name) for name in original.namelist()}
        files[self.player.name + '/web/main.dart.js'] = b'substituted runtime'
        with zipfile.ZipFile(archive, 'w') as bundle:
            for name, data in files.items():
                bundle.writestr(name, data)
        self.resign(archive)
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.run_prepare()

    def test_source_hash_or_tag_mismatch(self):
        for key, value in [('source_archive_sha256', '0' * 64), ('release_tag', 'nightly-999-1')]:
            with self.subTest(key=key):
                info = {**self.info, key: value}
                put(self.player, 'BUILD_INFO.json', json.dumps(info))
                (self.player / 'FILES.sha256').unlink()
                archive_package(self.player)
                with self.assertRaisesRegex(ValueError, 'metadata do not match'):
                    self.run_prepare()

    def test_bad_service_worker_manifest(self):
        put(self.player, 'web/main.dart.js', 'changed after worker injection')
        (self.player / 'FILES.sha256').unlink()
        archive_package(self.player)
        with self.assertRaisesRegex(ValueError, 'resource hash mismatch'):
            self.run_prepare()

    def resign(self, archive):
        archive.with_name(archive.name + '.sha256').write_text(f'{digest(archive)}  {archive.name}\n')

    def test_unsafe_zip_paths_rejected_before_extraction(self):
        archive = self.player.with_suffix('.zip')
        original = archive.read_bytes()
        for name in ('../escaped', '/absolute', 'C:/escape', 'folder\\escape',
                     self.player.name + '/web/../../escape'):
            with self.subTest(name=name):
                archive.write_bytes(original)
                with zipfile.ZipFile(archive, 'a') as bundle:
                    bundle.writestr(name, 'unsafe')
                self.resign(archive)
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    self.run_prepare()
                self.assertFalse(self.output.exists())

    def test_invalid_base_and_existing_output_rejected(self):
        for base in ('repo/', '/repo', '/../', '/repo/"/', '//'):
            with self.subTest(base=base), self.assertRaisesRegex(ValueError, 'Base path'):
                prepare_pages.prepare(self.downloads, self.output, base, self.tag)
        self.output.mkdir()
        put(self.output, 'existing', 'preserved')
        with self.assertRaisesRegex(ValueError, 'empty directory'):
            self.run_prepare()
        self.assertEqual((self.output / 'existing').read_text(), 'preserved')

    def test_infers_unambiguous_nightly_tag(self):
        result = prepare_pages.prepare(self.downloads, self.output, '/')
        self.assertEqual(result['tag'], self.tag)


if __name__ == '__main__':
    unittest.main()
