"""CI reuse must never bypass a failed shard or package mismatched build files."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ci_reuse
import ci_worker as ci
import package_release
from release_common import digest, file_hashes, write_json


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.artifacts = self.root / 'artifacts'
        self.expected = {'source_commit': 'a' * 40, 'toolchain': {'flutter_revision': 'b' * 40}}
        generated = self.root / 'upstream/lib/model.g.dart'
        generated.parent.mkdir(parents=True, exist_ok=True)
        generated.write_text('generated serializer')
        self.generated_hashes = {'lib/model.g.dart': digest(generated)}
        for name in ['a', 'b', 'c', 'd', 'e']:
            path = self.root / f'upstream/test/{name}_test.dart'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('test')
        identity = patch.object(ci, 'identity', return_value=self.expected)
        identity.start()
        self.addCleanup(identity.stop)
        for target in ci.BUILD_TARGETS:
            workers = [('checks', range(ci.SHARDS)), ('build', [0])] if target in ci.PLATFORMS else [('build', [0])]
            for kind, shards in workers:
                for shard in shards:
                    name = f'checks-{target}-{shard}' if kind == 'checks' else f'build-{target}'
                    info = {'schema': 1, **self.expected, 'kind': kind, 'platform': target,
                            'host_platform': 'linux' if target == 'web' else target,
                            'shard': shard if kind == 'checks' else None, 'shards': ci.SHARDS,
                            'run_id': '123', 'status': 'passed',
                            'generated_hashes': self.generated_hashes,
                            'steps': [{'name': step, 'exit_code': 0}
                                      for step in ci.required_steps(kind, target, shard)]}
                    if kind == 'checks':
                        info['test_files'] = ci.test_files(self.root, shard)
                    else:
                        generated_copy = self.artifacts / name / 'generated/lib/model.g.dart'
                        generated_copy.parent.mkdir(parents=True, exist_ok=True)
                        generated_copy.write_bytes(generated.read_bytes())
                        files = {
                            'linux': {'bundle': ['lcs_new_age', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so',
                                                 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']},
                            'web': {'web': ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js']},
                            'windows': {'native': ['lcs_new_age.exe', 'flutter_windows.dll', 'data/app.so',
                                                   'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']},
                        }[target]
                        for folder, entries in files.items():
                            for entry in entries:
                                path = self.artifacts / name / folder / entry
                                path.parent.mkdir(parents=True, exist_ok=True)
                                path.write_text('runtime')
                        info['payload_hashes'] = {folder: file_hashes(self.artifacts / name / folder) for folder in files}
                        if target == 'windows':
                            license_path = self.artifacts / name / 'Flutter-LICENSE.txt'
                            license_path.write_text('Flutter license')
                            info['flutter_license_hash'] = digest(license_path)
                    write_json(self.artifacts / name / 'report.json', info)

    def mutate(self, name, change):
        path = self.artifacts / name / 'report.json'
        info = json.loads(path.read_text())
        change(info)
        write_json(path, info)

    def test_complete_disjoint_test_coverage_and_valid_evidence(self):
        shards = [ci.test_files(self.root, shard) for shard in range(ci.SHARDS)]
        self.assertEqual(len(set().union(*map(set, shards))), sum(map(len, shards)))
        self.assertEqual(sum(map(len, shards)), 5)
        self.assertEqual(len(ci.verify_evidence(self.root, self.artifacts)), 11)

    def test_failed_missing_or_wrong_checks_are_rejected(self):
        path = self.artifacts / 'checks-windows-0/report.json'
        original = json.loads(path.read_text())
        for change in [lambda i: i.update(status='failed'),
                       lambda i: i.update(source_commit='c' * 40),
                       lambda i: i.update(toolchain={}),
                       lambda i: i['steps'].pop(),
                       lambda i: i['steps'][0].update(exit_code=1),
                       lambda i: i.update(test_files=[]),
                       lambda i: i.update(shard=1),
                       lambda i: i.update(run_id='124')]:
            with self.subTest(change=change):
                info = copy.deepcopy(original)
                change(info)
                write_json(path, info)
                with self.assertRaises(ValueError):
                    ci.verify_evidence(self.root, self.artifacts)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            ci.verify_evidence(self.root, self.artifacts)

    def test_payload_tampering_is_rejected(self):
        (self.artifacts / 'build-web/web/main.dart.js').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'hashes differ'):
            ci.verify_evidence(self.root, self.artifacts)

    def test_missing_web_build_or_wrong_host_is_rejected(self):
        self.mutate('build-web', lambda i: i.update(host_platform='windows'))
        with self.assertRaisesRegex(ValueError, 'Invalid or mismatched CI evidence'):
            ci.verify_evidence(self.root, self.artifacts)
        (self.artifacts / 'build-web/report.json').unlink()
        with self.assertRaises(FileNotFoundError):
            ci.verify_evidence(self.root, self.artifacts)

    def test_fourth_shard_is_required_on_each_operating_system(self):
        for target in ci.PLATFORMS:
            path = self.artifacts / f'checks-{target}-3/report.json'
            original = path.read_bytes()
            path.unlink()
            with self.subTest(platform=target), self.assertRaises(FileNotFoundError):
                ci.verify_evidence(self.root, self.artifacts)
            path.write_bytes(original)

    def test_web_manifest_must_be_injected(self):
        (self.artifacts / 'build-web/web/sw.js').write_text('const RESOURCES = null; // build: manifest')
        with self.assertRaisesRegex(ValueError, 'offline manifest'):
            ci.verify_evidence(self.root, self.artifacts)

    def test_wrong_selected_run_is_rejected(self):
        with patch.dict(os.environ, CI_ARTIFACT_RUN_ID='999'):
            with self.assertRaisesRegex(ValueError, 'selected run'):
                ci.verify_evidence(self.root, self.artifacts)

    def test_license_tampering_is_rejected(self):
        (self.artifacts / 'build-windows/Flutter-LICENSE.txt').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Flutter license'):
            ci.verify_evidence(self.root, self.artifacts)

    def test_generated_source_must_match_builds_and_checks(self):
        self.mutate('checks-windows-1', lambda i: i.update(generated_hashes={}))
        with self.assertRaisesRegex(ValueError, 'different generated source'):
            ci.verify_evidence(self.root, self.artifacts)

    def test_missing_generated_artifact_is_rejected(self):
        (self.artifacts / 'build-windows/generated/lib/model.g.dart').unlink()
        with self.assertRaisesRegex(ValueError, 'Generated source differs'):
            ci.verify_evidence(self.root, self.artifacts)

    def test_packager_cannot_trust_adapted_green_report_without_original_checks(self):
        report = ci.prepare_release(self.root, self.artifacts)
        original = report / 'ci/checks-linux-1/report.json'
        info = json.loads(original.read_text())
        info['status'] = 'failed'
        write_json(original, info)
        with self.assertRaisesRegex(ValueError, 'Invalid or mismatched CI evidence'):
            package_release.package(self.root, report, None, self.root / 'release',
                                    'test', None, 'owner/repo', linux=self.root / '.local/linux')

    def test_prepare_and_packaging_recheck_all_original_evidence(self):
        (self.root / 'upstream/lib/model.g.dart').unlink()
        report = ci.prepare_release(self.root, self.artifacts)
        self.assertEqual((self.root / 'upstream/lib/model.g.dart').read_text(), 'generated serializer')
        ci.verify_packaging_evidence(self.root, report, self.root / '.local/linux')
        (self.root / 'upstream/build/web/main.dart.js').write_text('changed after preparation')
        with self.assertRaisesRegex(ValueError, 'hashes differ'):
            ci.verify_packaging_evidence(self.root, report, self.root / '.local/linux')


class ReuseTests(unittest.TestCase):
    def setUp(self):
        self.run = {'id': 123, 'head_sha': 'a' * 40, 'head_branch': 'main',
                    'head_repository': {'full_name': 'owner/repo'}, 'event': 'push',
                    'path': '.github/workflows/checks.yml', 'status': 'completed', 'conclusion': 'success'}
        self.artifacts = [{'name': f'build-{target}', 'expired': False} for target in ci.BUILD_TARGETS] + [
            {'name': f'checks-{target}-{shard}', 'expired': False}
            for target in ci.PLATFORMS for shard in range(ci.SHARDS)]

    def test_only_exact_commit_and_trusted_push_workflow_qualifies(self):
        self.assertTrue(ci_reuse.eligible(self.run, 'owner/repo', 'a' * 40, 'main'))
        for field, value in [('head_sha', 'b' * 40), ('head_branch', 'feature'),
                             ('head_repository', {'full_name': 'fork/repo'}),
                             ('event', 'pull_request'), ('path', '.github/workflows/other.yml')]:
            with self.subTest(field=field):
                self.assertFalse(ci_reuse.eligible({**self.run, field: value}, 'owner/repo', 'a' * 40, 'main'))

    def test_missing_or_expired_artifacts_require_fresh_build(self):
        self.assertTrue(ci_reuse.complete_artifacts(self.artifacts))
        self.assertFalse(ci_reuse.complete_artifacts(self.artifacts[:-1]))
        self.assertFalse(ci_reuse.complete_artifacts([{**a, 'expired': True} for a in self.artifacts]))

    def test_successful_complete_run_is_reused(self):
        with patch.object(ci_reuse, 'api', side_effect=[{'workflow_runs': [self.run]}, {'artifacts': self.artifacts}]):
            self.assertEqual(ci_reuse.select_run('owner/repo', 'a' * 40, 'main', 0), '123')

    def test_failed_run_or_absent_artifact_falls_back(self):
        for replies in [[{'workflow_runs': [{**self.run, 'conclusion': 'failure'}]}],
                        [{'workflow_runs': [self.run]}, {'artifacts': []}],
                        [{'workflow_runs': []}]]:
            with patch.object(ci_reuse, 'api', side_effect=replies):
                self.assertEqual(ci_reuse.select_run('owner/repo', 'a' * 40, 'main', 0), '')

    def test_running_push_is_waited_for_then_reused(self):
        with patch.object(ci_reuse, 'api', side_effect=[
                {'workflow_runs': [{**self.run, 'status': 'in_progress'}]},
                {'workflow_runs': [self.run]}, {'artifacts': self.artifacts}]), \
                patch.object(ci_reuse.time, 'sleep') as sleep:
            self.assertEqual(ci_reuse.select_run('owner/repo', 'a' * 40, 'main'), '123')
        sleep.assert_called_once()
        self.assertLessEqual(sleep.call_args.args[0], 10)


if __name__ == '__main__':
    unittest.main()
