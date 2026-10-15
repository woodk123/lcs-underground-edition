"""Size accounting covers real compressed bytes and rejects oversized players."""
from pathlib import Path
import tempfile
import unittest
import zipfile

from release_sizes import PLAYER_BUDGETS, check_budget, measure_archive


class ReleaseSizeTests(unittest.TestCase):
    def test_zip_accounting_separates_art_and_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Player.zip'
            data = {'web/assets/assets/modern/portraits_v2/batch_00.webp': b'portrait' * 100,
                    'web/assets/assets/modern/paper.webp': b'paper' * 100,
                    'web/canvaskit/canvaskit.wasm': b'renderer' * 100,
                    'web/main.dart.js': b'code' * 100}
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                for name, content in data.items():
                    archive.writestr('Player/' + name, content)
            measured = measure_archive(path)
            self.assertEqual(measured['archive_bytes'], path.stat().st_size)
            self.assertEqual(measured['extracted_bytes'], sum(map(len, data.values())))
            self.assertEqual(set(measured['groups']),
                             {'portraits', 'other_artwork', 'web_renderers', 'code_and_runtime'})
            self.assertLess(sum(g['archive_bytes'] for g in measured['groups'].values()), measured['extracted_bytes'])

    def test_download_and_extracted_budgets_are_enforced_independently(self):
        limits = PLAYER_BUDGETS['windows-x64']
        self.assertEqual(check_budget('windows-x64', limits), [])
        for field in limits:
            errors = check_budget('windows-x64', {**limits, field: limits[field] + 1})
            self.assertEqual(len(errors), 1)
            self.assertIn(field, errors[0])


if __name__ == '__main__':
    unittest.main()
