"""Pages selects published managed nightlies, never a preview or draft."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import download_pages_nightly as pages
from nightly_release import MARKER


def nightly(**extra):
    tag = 'nightly-123-1'
    return {'name': 'Nightly', 'prerelease': True, 'tag_name': tag,
            'body': MARKER + 'a' * 64 + ' -->', 'draft': False,
            'published_at': '2026-10-17T06:00:00Z',
            'assets': [{'name': f'LCS-Underground-Edition-{tag}-{target}.zip{suffix}'}
                       for target in ('Web-Player', 'Source') for suffix in ('', '.sha256')],
            **extra}


class DownloadTests(unittest.TestCase):
    def test_only_latest_published_managed_nightly_is_downloaded(self):
        items = [nightly(), nightly(draft=True, published_at='2026-10-18T06:00:00Z'),
                 nightly(tag_name='underground-preview-2026.10.17',
                         published_at='2026-10-19T06:00:00Z')]
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(pages, 'releases', return_value=items), \
                patch.object(pages, 'gh') as github, patch.dict('os.environ', {}, clear=True):
            tag = pages.download('owner/repo', Path(temporary) / 'downloads')
            self.assertEqual(tag, 'nightly-123-1')
            arguments = github.call_args.args
            self.assertEqual(arguments[:3], ('release', 'download', tag))
            self.assertEqual(arguments.count('--pattern'), 4)

    def test_missing_source_prevents_download(self):
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(pages, 'releases', return_value=[nightly(assets=[])]), \
                patch.object(pages, 'gh') as github:
            with self.assertRaisesRegex(ValueError, 'missing web/source'):
                pages.download('owner/repo', Path(temporary) / 'downloads')
            github.assert_not_called()

    def test_no_published_nightly_prevents_download(self):
        with patch.object(pages, 'releases', return_value=[nightly(draft=True)]), \
                patch.object(pages, 'gh') as github:
            with self.assertRaisesRegex(ValueError, 'No successfully published'):
                pages.download('owner/repo', Path('unused'))
            github.assert_not_called()


if __name__ == '__main__':
    unittest.main()
