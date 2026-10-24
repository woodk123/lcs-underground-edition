"""The development build cache must reject changed source and tampered artifacts."""
import json
import io
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import tempfile
import subprocess
import sys
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
                     'build_id': 'aaaaaaaa-bbbbbbbb',
                     'main_js_sha256': digest(self.web / 'main.dart.js'),
                     'payload_hashes': file_hashes(self.web)}
        self.path = self.web.parent / 'build.json'
        self.write()

    def write(self):
        self.path.write_text(json.dumps(self.info))

    def test_unchanged_build_reuses_but_malformed_or_changed_inputs_invalidate(self):
        self.assertEqual(prepare.cached_build(self.path, self.source, self.web), self.info)
        for key in self.source:
            changed = {**self.source, key: 'changed'}
            self.assertIsNone(prepare.cached_build(self.path, changed, self.web))
        changed = {'commit': 'c' * 40, 'inputs_sha256': 'b' * 8 + 'c' * 56}
        self.assertIsNone(prepare.cached_build(self.path, changed, self.web), 'Compare the full fingerprint, not its build-ID prefix.')

    def test_commit_only_change_preserves_compiled_identity_and_manifest_bytes(self):
        before = self.path.read_bytes()
        current = {**self.source, 'commit': 'c' * 40}
        reused = prepare.cached_build(self.path, current, self.web)
        self.assertEqual(reused, self.info)
        self.assertEqual(reused['source'], self.source)
        self.assertNotEqual(reused['source']['commit'], current['commit'])
        self.assertEqual(self.path.read_bytes(), before)

    def test_normal_cli_retains_existing_fields_and_reports_both_sources(self):
        current = {**self.source, 'commit': 'c' * 40}
        output = io.StringIO()
        with patch.object(prepare, 'prepare', return_value={**self.info, 'checked_source': current}), \
                patch.object(sys, 'argv', ['prepare_dev_mcp.py']), redirect_stdout(output):
            prepare.main()
        summary, _ = json.JSONDecoder().raw_decode(output.getvalue())
        self.assertEqual(summary, {
            **{key: self.info[key] for key in ('web_root', 'build_id', 'main_js_sha256', 'source')},
            'checked_source': current})

    def test_missing_malformed_and_inconsistent_original_identities_invalidate(self):
        for source in (None, [], {}, {'commit': 'a' * 40}, {'inputs_sha256': 'b' * 64},
                       {'commit': 7, 'inputs_sha256': 'b' * 64},
                       {'commit': 'a' * 40, 'inputs_sha256': None},
                       {'commit': 'a' * 39, 'inputs_sha256': 'b' * 64},
                       {'commit': 'a' * 40, 'inputs_sha256': 'b' * 63}):
            with self.subTest(source=source):
                self.assertIsNone(prepare.cached_build(self.path, source, self.web))
                self.info['source'] = source
                self.write()
                self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))
                self.assertIsNone(prepare.cached_build(self.path, source, self.web))
                self.info['source'] = self.source
                self.write()
        for build_id in (None, 1, '', 'changed', 'cccccccc-bbbbbbbb', 'aaaaaaaa-cccccccc'):
            with self.subTest(build_id=build_id):
                self.info['build_id'] = build_id
                self.write()
                self.assertIsNone(prepare.cached_build(self.path, self.source, self.web))

    def test_real_non_compiled_commit_reuses_and_check_reports_both_sources_without_writes(self):
        def git(*arguments):
            return subprocess.run(['git', '-C', str(self.root), *arguments], check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (self.root / '.gitignore').write_text('.local/\n*.g.dart\n')
        source = self.root / 'upstream/lib/model.dart'
        source.parent.mkdir(parents=True)
        source.write_text("part 'model.g.dart';\n")
        source.with_name('model.g.dart').write_text('unchanged ignored serializer')
        readme = self.root / 'README.md'
        readme.write_text('first documentation')
        git('init', '-q')
        git('add', '.')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'compiled fixture')
        compiled = prepare.source_identity(self.root)
        self.info['source'] = compiled
        self.info['build_id'] = f'{compiled["commit"][:8]}-{compiled["inputs_sha256"][:8]}'
        self.write()
        readme.write_text('updated documentation')
        for name in ('upstream/test/model_test.dart', 'scripts/browser_review.mjs'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('non-compiled check change')
        git('add', '.')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'docs and checks only')
        current = prepare.source_identity(self.root)
        self.assertNotEqual(current['commit'], compiled['commit'])
        self.assertEqual(current['inputs_sha256'], compiled['inputs_sha256'])
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        self.assertEqual(prepare.cached_build(self.path, current, self.web), self.info)
        output = io.StringIO()
        with patch.object(prepare, 'ROOT', self.root), \
                patch.object(sys, 'argv', ['prepare_dev_mcp.py', '--check']), redirect_stdout(output):
            prepare.main()
        self.assertEqual(json.loads(output.getvalue()), {
            **{key: self.info[key] for key in ('web_root', 'build_id', 'main_js_sha256', 'source')},
            'checked_source': current})
        self.assertEqual({path.relative_to(self.root): path.read_bytes()
                          for path in self.root.rglob('*') if path.is_file()}, before)
        source.write_text('runtime input changed after the docs commit')
        self.assertIsNone(prepare.cached_build(self.path, prepare.source_identity(self.root), self.web))
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        errors = io.StringIO()
        with patch.object(prepare, 'ROOT', self.root), patch.object(prepare, 'run') as commands, \
                patch.object(sys, 'argv', ['prepare_dev_mcp.py', '--check']), redirect_stderr(errors):
            with self.assertRaises(SystemExit) as rejected:
                prepare.main()
        self.assertEqual(rejected.exception.code, 1)
        self.assertIn('missing, stale or modified', errors.getvalue())
        commands.assert_not_called()
        self.assertEqual({path.relative_to(self.root): path.read_bytes()
                          for path in self.root.rglob('*') if path.is_file()}, before)

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
        self.info['build_id'] = f'{original["commit"][:8]}-{original["inputs_sha256"][:8]}'
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
        self.info['build_id'] = f'{original["commit"][:8]}-{original["inputs_sha256"][:8]}'
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
