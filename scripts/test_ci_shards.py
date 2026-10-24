"""Coverage and timing parsing for balanced CI test shards."""
import json
from pathlib import Path
import tempfile
import unittest

from ci_shards import SHARDS, suite_seconds, test_files, timing_profile


class ShardTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'upstream/test').mkdir(parents=True)
        for name in ('a', 'b', 'c', 'd', 'e', 'f'):
            (self.root / f'upstream/test/{name}_test.dart').write_text('fixture')

    def profile(self, weights=None, extra=None):
        (self.root / 'scripts').mkdir(exist_ok=True)
        value = {'schema': 1, 'platforms': {target: {
            'files': weights or {f'test/{name}_test.dart': 10 for name in ('a', 'b', 'c', 'd', 'e', 'f')},
            'extra_seconds': extra if extra is not None else [20, *([0] * (SHARDS - 1))],
        } for target in ('windows', 'linux')}}
        (self.root / 'scripts/ci_test_weights.json').write_text(json.dumps(value))

    def test_extra_analysis_budget_moves_test_work_to_other_shard(self):
        self.profile()
        groups = [test_files(self.root, shard) for shard in range(SHARDS)]
        self.assertLess(len(groups[0]), max(map(len, groups[1:])))
        self.assertEqual(len(set().union(*map(set, groups))), sum(map(len, groups)))
        self.assertEqual(sum(map(len, groups)), 6)
        first = groups[0]
        self.assertEqual(first, test_files(self.root, 0))

    def test_new_and_deleted_tests_do_not_change_complete_coverage(self):
        self.profile()
        (self.root / 'upstream/test/new_test.dart').write_text('new')
        (self.root / 'upstream/test/a_test.dart').unlink()
        groups = [test_files(self.root, shard) for shard in range(SHARDS)]
        expected = {p.relative_to(self.root / 'upstream').as_posix()
                    for p in (self.root / 'upstream/test').glob('*_test.dart')}
        self.assertEqual(set().union(*map(set, groups)), expected)
        self.assertEqual(len(set().union(*map(set, groups))), sum(map(len, groups)))

    def test_large_overhead_keeps_shards_nonempty(self):
        self.profile(extra=[1000, *([0] * (SHARDS - 1))])
        self.assertTrue(all(test_files(self.root, shard) for shard in range(SHARDS)))

    def test_invalid_costs_are_rejected(self):
        self.profile(weights={'test/a_test.dart': -1})
        with self.assertRaisesRegex(ValueError, 'Invalid test timing weights'):
            test_files(self.root, 0)

    def test_json_parser_includes_loading_and_hidden_setup(self):
        path = self.root / 'tests.jsonl'
        events = [
            {'type': 'suite', 'suite': {'id': 1, 'path': 'D:/a/project/upstream/test/a_test.dart'}},
            {'type': 'testStart', 'time': 0, 'test': {'id': 2, 'suiteID': 1}},
            {'type': 'testDone', 'time': 1000, 'testID': 2},
            {'type': 'testStart', 'time': 1001, 'test': {'id': 3, 'suiteID': 1}},
            {'type': 'testDone', 'time': 2500, 'testID': 3, 'hidden': True},
            {'type': 'done', 'success': True},
        ]
        path.write_text('\n'.join(json.dumps(event) for event in events))
        self.assertEqual(suite_seconds(path, ['test/a_test.dart']), {'test/a_test.dart': 2.5})
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            suite_seconds(path, ['test/a_test.dart', 'test/b_test.dart'])
        events[-1]['success'] = False
        path.write_text('\n'.join(json.dumps(event) for event in events))
        with self.assertRaisesRegex(ValueError, 'unsuccessful'):
            suite_seconds(path, ['test/a_test.dart'])

    def timing_reports(self):
        """Eight actual-format reports with a separate enabled bridge run."""
        for target in ('linux', 'windows'):
            for shard in range(SHARDS):
                folder = self.root / f'artifacts/checks-{target}-{shard}'
                folder.mkdir(parents=True)
                name = f'test/shard_{shard}_test.dart'
                steps = [
                    {'name': 'dependencies', 'exit_code': 0, 'elapsed_seconds': 100},
                    {'name': 'serialization', 'exit_code': 0, 'elapsed_seconds': 100},
                    {'name': 'tests', 'exit_code': 0, 'elapsed_seconds': 4},
                ]
                if shard == 0:
                    steps.extend({'name': step, 'exit_code': 0, 'elapsed_seconds': seconds}
                                 for step, seconds in [('development-bridge', 12), ('tooling', 3),
                                                       ('assets', 2), ('focused-analysis', 5),
                                                       ('full-analysis', 8)])
                report = {'status': 'passed', 'source_commit': 'a' * 40, 'run_id': '123',
                          'platform': target, 'shard': shard, 'shards': SHARDS,
                          'test_files': [name], 'steps': steps}
                (folder / 'report.json').write_text(json.dumps(report))
                events = [
                    {'type': 'suite', 'suite': {'id': 1, 'path': f'/checkout/upstream/{name}'}},
                    {'type': 'testStart', 'time': 0, 'test': {'id': 2, 'suiteID': 1}},
                    {'type': 'testDone', 'time': 1000, 'testID': 2},
                    {'type': 'done', 'success': True},
                ]
                (folder / 'tests.jsonl').write_text('\n'.join(map(json.dumps, events)))
        return self.root / 'artifacts'

    def test_timing_profile_budgets_enabled_bridge_without_duplicating_suite_cost(self):
        artifacts = self.timing_reports()
        profile = timing_profile(artifacts)
        for target in ('linux', 'windows'):
            self.assertEqual(profile['platforms'][target]['extra_seconds'], [30, 0, 0, 0])
            self.assertEqual(profile['platforms'][target]['files'], {
                f'test/shard_{shard}_test.dart': 4 for shard in range(SHARDS)})
        # Rebalance using the refreshed profile; every suite still runs once.
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/ci_test_weights.json').write_text(json.dumps(profile))
        groups = [test_files(self.root, shard) for shard in range(SHARDS)]
        self.assertEqual(len(set().union(*map(set, groups))), 6)
        self.assertEqual(sum(map(len, groups)), 6)

    def test_timing_profile_rejects_failed_mismatched_and_overlapping_reports(self):
        artifacts = self.timing_reports()
        path = artifacts / 'checks-windows-0/report.json'
        original = json.loads(path.read_text())
        for update in ({'run_id': 'different'}, {'source_commit': 'b' * 40}, {'status': 'failed'}):
            with self.subTest(update=update):
                path.write_text(json.dumps({**original, **update}))
                with self.assertRaises(ValueError):
                    timing_profile(artifacts)
        path.write_text(json.dumps(original))
        failed = {**original, 'steps': [dict(step) for step in original['steps']]}
        failed['steps'][3]['exit_code'] = 1
        path.write_text(json.dumps(failed))
        with self.assertRaisesRegex(ValueError, 'successful'):
            timing_profile(artifacts)
        path.write_text(json.dumps(original))
        # A shard cannot claim another shard's suite even with valid JSON events.
        other = artifacts / 'checks-windows-1'
        report = json.loads((other / 'report.json').read_text())
        report['test_files'] = original['test_files']
        (other / 'report.json').write_text(json.dumps(report))
        (other / 'tests.jsonl').write_bytes((path.parent / 'tests.jsonl').read_bytes())
        with self.assertRaisesRegex(ValueError, 'overlap'):
            timing_profile(artifacts)


if __name__ == '__main__':
    unittest.main()
