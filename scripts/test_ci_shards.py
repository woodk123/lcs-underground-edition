"""Coverage and timing parsing for balanced CI test shards."""
import json
from pathlib import Path
import tempfile
import unittest

from ci_shards import suite_seconds, test_files


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
            'extra_seconds': extra if extra is not None else [20, 0],
        } for target in ('windows', 'linux')}}
        (self.root / 'scripts/ci_test_weights.json').write_text(json.dumps(value))

    def test_extra_analysis_budget_moves_test_work_to_other_shard(self):
        self.profile()
        first, second = [test_files(self.root, shard) for shard in range(2)]
        self.assertEqual(len(first), 2)
        self.assertEqual(len(second), 4)
        self.assertFalse(set(first) & set(second))
        self.assertEqual(len(first) + len(second), 6)
        self.assertEqual(first, test_files(self.root, 0))

    def test_new_and_deleted_tests_do_not_change_complete_coverage(self):
        self.profile()
        (self.root / 'upstream/test/new_test.dart').write_text('new')
        (self.root / 'upstream/test/a_test.dart').unlink()
        groups = [test_files(self.root, shard) for shard in range(2)]
        expected = {p.relative_to(self.root / 'upstream').as_posix()
                    for p in (self.root / 'upstream/test').glob('*_test.dart')}
        self.assertEqual(set(groups[0]) | set(groups[1]), expected)
        self.assertFalse(set(groups[0]) & set(groups[1]))

    def test_large_overhead_keeps_shards_nonempty(self):
        self.profile(extra=[1000, 0])
        self.assertTrue(test_files(self.root, 0))
        self.assertTrue(test_files(self.root, 1))

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


if __name__ == '__main__':
    unittest.main()
