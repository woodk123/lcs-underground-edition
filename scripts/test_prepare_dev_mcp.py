"""The development build cache must reject changed source and tampered artifacts."""
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

import prepare_dev_mcp as prepare
from release_common import digest, file_hashes


class DevelopmentBuildTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.web = self.root / '.local/dev-mcp/web'
        self.web.mkdir(parents=True)
        for name in ('index.html', 'main.dart.js', 'sw.js'):
            (self.web / name).write_text(name)
        self.source = {'commit': 'a' * 40, 'inputs_sha256': 'b' * 64}
        self.info = {'schema': 1, 'status': 'ready', 'devtools': True,
                     'source': self.source, 'web_root': str(self.web),
                     'main_js_sha256': digest(self.web / 'main.dart.js'),
                     'payload_hashes': file_hashes(self.web)}
        self.path = self.web.parent / 'build.json'
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.info))

    def test_unchanged_build_reuses_but_source_changes_invalidate(self):
        self.assertEqual(prepare.cached_build(self.path, self.source, self.web), self.info)
        for key in self.source:
            changed = {**self.source, key: 'changed'}
            self.assertIsNone(prepare.cached_build(self.path, changed, self.web))

    def test_modified_extra_missing_and_incomplete_outputs_invalidate(self):
        for name in ('index.html', 'main.dart.js', 'sw.js', 'extra.txt'):
            path = self.web / name
            original = path.read_bytes() if path.exists() else None
            path.write_text('tampered')
            self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))
            path.unlink()
            if original is not None:
                self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))
                path.write_bytes(original)
        self.info['status'] = 'building'
        self.write()
        self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))

    def test_invalid_metadata_and_wrong_bridge_or_directory_invalidate(self):
        for key, value in [('devtools', False), ('web_root', 'elsewhere'), ('main_js_sha256', 'bad')]:
            original = self.info[key]
            self.info[key] = value
            self.write()
            self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))
            self.info[key] = original
        self.path.write_text('interrupted')
        self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))

    def test_output_stays_inside_ignored_directories(self):
        for name in ('.', 'upstream/build/web', '.local', 'reports', '../other'):
            with self.assertRaises(ValueError):
                prepare.output_directory(self.root, name)
        self.assertEqual(prepare.output_directory(self.root, 'reports/mcp'), self.root / 'reports/mcp')

    def test_source_fingerprint_tracks_new_changed_and_missing_game_inputs(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        game_file = self.root / 'upstream/lib/game.dart'
        game_file.parent.mkdir(parents=True)
        game_file.write_text('first')
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        first = prepare.source_identity(self.root)
        game_file.write_text('changed')
        changed = prepare.source_identity(self.root)
        self.assertEqual(first['commit'], changed['commit'])
        self.assertNotEqual(first['inputs_sha256'], changed['inputs_sha256'])
        new_file = game_file.with_name('new.dart')
        new_file.write_text('untracked input')
        self.assertNotEqual(prepare.source_identity(self.root), changed)
        new_file.unlink()
        game_file.unlink()
        self.assertNotEqual(prepare.source_identity(self.root), first)

    def test_compilation_recipe_edits_invalidate_the_compiled_cache(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        recipes = [self.root / 'scripts' / name for name in ('prepare_dev_mcp.py', 'release_common.py')]
        for path in recipes:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original recipe')
        subprocess.run(['git', '-C', str(self.root), 'add', 'scripts'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        self.info['source'] = original = prepare.source_identity(self.root)
        self.write()
        self.assertEqual(prepare.cached_build(self.path, original, self.web), self.info)
        for path in recipes:
            with self.subTest(recipe=path.name):
                path.write_text('changed compilation recipe')
                current = prepare.source_identity(self.root)
                self.assertIsNone(prepare.cached_build(self.path, current, self.web),
                                  'An edited build recipe must not reuse its previous compiled player.')
                path.write_text('original recipe')
        unrelated = self.root / 'scripts/unrelated_tool.py'
        unrelated.write_text('does not compile the development player')
        self.assertEqual(prepare.source_identity(self.root), original)

    def test_ignored_generated_serializers_are_compilation_inputs(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / '.gitignore').write_text('*.g.dart\n*.tmp\n.local/\n')
        source = self.root / 'upstream/lib/model.dart'
        source.parent.mkdir(parents=True)
        source.write_text("part 'model.g.dart';\n")
        generated = source.with_name('model.g.dart')
        generated.write_text('original generated serializer')
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        ignored = subprocess.check_output(['git', '-C', str(self.root), 'ls-files',
                                           '--others', '--ignored', '--exclude-standard'], text=True)
        self.assertIn('upstream/lib/model.g.dart', ignored)
        self.info['source'] = original = prepare.source_identity(self.root)
        self.write()
        self.assertEqual(prepare.cached_build(self.path, original, self.web), self.info)
        generated.write_text('edited generated serializer')
        changed = prepare.source_identity(self.root)
        self.assertEqual(changed['commit'], original['commit'])
        self.assertNotEqual(changed, original)
        self.assertIsNone(prepare.cached_build(self.path, changed, self.web))
        generated.unlink()
        self.assertIsNone(prepare.cached_build(self.path, prepare.source_identity(self.root), self.web))
        generated.write_text('original generated serializer')
        self.assertEqual(prepare.source_identity(self.root), original)
        unrelated = generated.with_suffix('.tmp')
        unrelated.write_text('temporary non-source output')
        self.assertEqual(prepare.source_identity(self.root), original)

    def test_font_edits_additions_and_deletions_change_the_fingerprint(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        font = self.root / 'upstream/fonts/journal/example.ttf'
        font.parent.mkdir(parents=True)
        font.write_bytes(b'original font fixture')
        subprocess.run(['git', '-C', str(self.root), 'add', 'upstream'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        original = prepare.source_identity(self.root)
        font.write_bytes(b'changed font fixture')
        self.assertNotEqual(prepare.source_identity(self.root), original)
        font.unlink()
        removed = prepare.source_identity(self.root)
        self.assertNotEqual(removed, original)
        font.with_name('new.ttf').write_bytes(b'new untracked font')
        self.assertNotEqual(prepare.source_identity(self.root), removed)

    def test_project_connection_preserves_settings_is_idempotent_and_rejects_conflicts(self):
        path = self.root / '.codex/config.toml'
        path.parent.mkdir()
        original = '# retain this comment\n[existing]\nvalue = 7\n'
        path.write_text(original)
        with patch.object(prepare.shutil, 'which', return_value='C:/node/node.exe'):
            self.assertEqual(prepare.configure_codex(self.root), path)
            first = path.read_text()
            self.assertTrue(first.startswith(original))
            prepare.configure_codex(self.root)
            self.assertEqual(path.read_text(), first)
            path.write_text(first.replace('tool_timeout_sec = 60', 'tool_timeout_sec = 20'))
            with self.assertRaisesRegex(ValueError, 'differently'):
                prepare.configure_codex(self.root)


if __name__ == '__main__':
    unittest.main()
