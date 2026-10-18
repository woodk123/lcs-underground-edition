"""Pages selects published managed nightlies or explicitly requested numbered releases."""
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
    def test_explicit_numbered_release_downloads_exact_assets(self):
        tag = 'underground-v0.1.0'
        release = nightly(tag_name=tag, prerelease=False, body='Short release notes')
        release['assets'] = [{'name': a['name'].replace('nightly-123-1', tag)}
                             for a in release['assets']]
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(pages, 'releases', return_value=[nightly(), release]), \
                patch.object(pages, 'gh') as github:
            self.assertEqual(pages.download('owner/repo', Path(temporary) / 'release', tag), tag)
            self.assertEqual(github.call_args.args[:3], ('release', 'download', tag))
            self.assertIn(f'LCS-Underground-Edition-{tag}-Source.zip.sha256', github.call_args.args)

    def test_numbered_release_rejects_drafts_prereleases_and_invalid_tags(self):
        for overrides in ({'draft': True}, {'prerelease': True}, {'published_at': None}):
            release = nightly(tag_name='underground-v0.1.0', prerelease=False)
            release.update(overrides)
            with self.subTest(overrides=overrides), \
                    patch.object(pages, 'releases', return_value=[release]), \
                    patch.object(pages, 'gh') as github:
                with self.assertRaisesRegex(ValueError, 'not publicly published'):
                    pages.download('owner/repo', Path('unused'), 'underground-v0.1.0')
                github.assert_not_called()
        with self.assertRaisesRegex(ValueError, 'numbered'):
            pages.download('owner/repo', Path('unused'), '../other')

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
