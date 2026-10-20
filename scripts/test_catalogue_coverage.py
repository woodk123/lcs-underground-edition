"""Regression checks for incomplete or misleading catalogue asset manifests."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from verify_assets import verify


class CatalogueCoverageTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[1]

    def corrupted(self, mutate, expected):
        decode = json.loads

        def read(value, **kwargs):
            result = decode(value, **kwargs)
            mutate(result)
            return result

        with patch('verify_assets.json.loads', side_effect=read):
            with self.assertRaisesRegex(ValueError, expected):
                verify(self.root)

    def test_missing_authored_record_is_rejected(self):
        def mutate(data):
            if 'catalogues' in data:
                data['catalogues'].pop()
        self.corrupted(mutate, 'Coverage inventory differs')

    def test_missing_painting_is_rejected(self):
        def mutate(data):
            if data.get('equipment_paintings') == 145:
                data['assets'][-1]['entries'].pop()
        self.corrupted(mutate, 'Missing or unexpected catalogue paintings')

    def test_required_item_cannot_be_excluded(self):
        def mutate(data):
            if 'catalogues' in data:
                data['catalogues'][1]['illustration_required'] = False
        self.corrupted(mutate, 'Unexpected unillustrated')

    def test_duplicate_identity_is_rejected(self):
        def mutate(data):
            if data.get('equipment_paintings') == 145:
                data['assets'][-1]['entries'].append(data['assets'][0]['entries'][0])
        self.corrupted(mutate, 'Duplicate catalogue painting')

    def test_out_of_bounds_crop_is_rejected(self):
        def mutate(data):
            if data.get('equipment_paintings') == 145:
                data['assets'][-1]['entries'][0]['source_rect'] = [1530, 0, 50, 50]
        self.corrupted(mutate, 'Invalid catalogue crop')


if __name__ == '__main__':
    unittest.main()
