"""Local documentation checks must catch broken guidance without running examples."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import verify_docs


class MaintainedDocumentationTests(unittest.TestCase):
    def test_this_checkouts_maintained_links_without_git_sdk_or_powershell(self):
        # Source ZIPs retain this layout; locating the root needs no Git metadata.
        root = Path(__file__).resolve().parent.parent
        with patch.object(verify_docs.subprocess, 'run', side_effect=AssertionError('Local link checks must not launch tools.')):
            report = verify_docs.verify(root)
        self.assertEqual(report['status'], 'passed', json.dumps(report['issues'], indent=2))


class DocumentationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lcs docs ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / 'checkout with spaces'
        self.put('AGENTS.md', '# Repository policy\n')
        self.put('README.md', '# Main\n')
        (self.root / 'docs').mkdir()

    def put(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, bytes):
            path.write_bytes(contents)
        else:
            path.write_text(contents, encoding='utf-8')
        return path

    def verify(self, expected='passed', **kwargs):
        report = verify_docs.verify(self.root, **kwargs)
        self.assertEqual(report['status'], expected, report['issues'])
        return report

    def test_default_scope_includes_nested_guides_and_skills_without_git_or_sdk(self):
        self.put('README.md', '# Main\n[guide](docs/guide.md#start)\n![face](docs/face.png)\n')
        self.put('docs/guide.md', '# Start\n[policy](../AGENTS.md#repository-policy)\n')
        self.put('docs/face.png', b'\xff\x00binary image')
        self.put('docs/nested/Upper.MD', '# Nested\n[home](../../README.md#main)\n')
        self.put('.agents/skills/demo/SKILL.md', '# Skill\n[guide](../../../docs/guide.md)\n')
        self.put('upstream/README.md', '[unmaintained](missing.md)\n')
        self.put('.local/review/README.md', '[generated](missing.md)\n')
        with patch.object(verify_docs, 'powershell_issues') as parser:
            report = self.verify()
        parser.assert_not_called()
        self.assertEqual(report['files'], 5)
        self.assertEqual(report['local_links'], 5)
        self.assertEqual(report['powershell']['status'], 'not-requested')

    def test_missing_file_and_anchor_report_the_source_line_and_destination(self):
        self.put('README.md', '# Main\n[missing](docs/gone.md)\n[anchor](docs/guide.md#gone)\n')
        self.put('docs/guide.md', '# Present\n')
        report = self.verify('failed')
        self.assertEqual([(issue['file'], issue['line'], issue['target']) for issue in report['issues']],
                         [('README.md', 2, 'docs/gone.md'), ('README.md', 3, 'docs/guide.md#gone')])
        self.assertIn('does not exist', report['issues'][0]['message'])
        self.assertIn('anchor', report['issues'][1]['message'])

    def test_heading_formatting_unicode_duplicates_setext_and_explicit_anchors(self):
        self.put('docs/guide.md', '# Use **crew** and `orders()`\n## Café (ready!)\n'
                 '## Same\n## Same\n## Same-1\nSetext title\n===\n<a id="details"></a>\n')
        targets = ('use-crew-and-orders', 'caf%C3%A9-ready', 'same', 'same-1', 'same-1-1', 'setext-title', 'details')
        self.put('README.md', '# Main\n' + ''.join(f'[go](docs/guide.md#{target})\n' for target in targets))
        self.assertEqual(self.verify()['local_links'], len(targets))
        self.put('README.md', '[wrong case](docs/guide.md#Same)\n')
        self.verify('failed')

    def test_fenced_inline_indented_code_and_skill_frontmatter_are_not_links_or_headings(self):
        self.put('.agents/skills/demo/SKILL.md', '---\ndescription: [example](missing.md)\n---\n'
                 '# Skill\n[home](../../../README.md#main)\n')
        self.put('README.md', '# Main\n`[inline](missing.md)` and ``[code ` here](missing.md)``\n'
                 '````markdown\n# False heading\n```\n[example](missing.md)\n````\n'
                 '~~~\n[tilde](missing.md)\n~~~\n'
                 '    [indented](missing.md)\n\t[tab](missing.md)\n'
                 '\\[escaped](missing.md)\n[real](#main)\n')
        self.assertEqual(self.verify()['local_links'], 2)
        self.put('README.md', '```markdown\n# False heading\n```\n[bad](#false-heading)\n')
        self.assertIn('anchor', self.verify('failed')['issues'][0]['message'])

    def test_unclosed_fence_and_link_fail_without_treating_example_links_as_targets(self):
        self.put('README.md', '[broken](docs/file.md\n')
        self.assertIn('Unclosed link', self.verify('failed')['issues'][0]['message'])
        self.put('README.md', '~~~markdown\n[example](missing.md)\n')
        report = self.verify('failed')
        self.assertEqual(report['local_links'], 0)
        self.assertEqual(report['issues'][0]['line'], 1)
        self.assertIn('Unclosed code fence', report['issues'][0]['message'])

    def test_images_directories_parentheses_spaces_titles_and_percent_encoding(self):
        self.put('docs/file (draft).md', '# Draft\n')
        self.put('docs/photo(1).png', b'not decoded by the link checker')
        self.put('README.md', '[folder](docs/)\n![portrait](docs/photo(1).png "Face")\n'
                 '[spaces](<docs/file (draft).md> "Draft guide")\n'
                 '[encoded](docs/file%20%28draft%29.md#draft)\n'
                 '[escaped](docs/photo\\(1\\).png)\n[query](README.md?plain=1#main)\n# Main\n')
        self.assertEqual(self.verify()['local_links'], 6)
        self.put('README.md', '![missing](docs/no-image.png)\n')
        self.assertEqual(self.verify('failed')['issues'][0]['target'], 'docs/no-image.png')

    def test_linked_image_destination_is_checked_inside_local_and_external_links(self):
        self.put('docs/guide.md', '# Guide\n')
        for outer in ('docs/guide.md', 'https://example.invalid/guide'):
            with self.subTest(outer=outer):
                self.put('README.md', f'# Main\n[![preview](docs/missing.png)]({outer})\n')
                report = self.verify('failed')
                self.assertEqual([(issue['file'], issue['line'], issue['target']) for issue in report['issues']],
                                 [('README.md', 2, 'docs/missing.png')])
                image = self.put('docs/missing.png', b'present image fixture')
                self.verify()
                image.unlink()

    def test_linked_reference_image_uses_document_definitions_and_its_actual_line(self):
        self.put('docs/guide.md', '# Guide\n')
        self.put('README.md', '# Main\n[\n ![preview][IMAGE]\n](docs/guide.md)\n[image]: docs/photo.png\n')
        report = self.verify('failed')
        self.assertEqual([(issue['line'], issue['target']) for issue in report['issues']],
                         [(3, 'docs/photo.png')])
        self.put('docs/photo.png', b'present referenced image')
        self.assertEqual(self.verify()['local_links'], 2)

    def test_escaped_and_code_linked_image_examples_remain_excluded(self):
        self.put('docs/guide.md', '# Guide\n')
        self.put('README.md', '# Main\n' + r'\!\[preview\](missing.png)' + '\n'
                 '`[![preview](missing.png)](missing.md)`\n'
                 '```markdown\n[![preview](missing.png)](missing.md)\n```\n'
                 '[label `![preview](missing.png)`](docs/guide.md)\n')
        self.assertEqual(self.verify()['local_links'], 1)

    def test_reference_links_images_shortcuts_and_casefolded_labels(self):
        self.put('docs/guide.md', '# Start\n')
        self.put('docs/photo.png', b'image')
        self.put('README.md', '[guide][DOC]\n[doc][]\n[Doc]\n![face][image]\n[plain brackets]\n'
                 '[doc]: docs/guide.md#start "Guide title"\n[image]: <docs/photo.png>\n')
        self.assertEqual(self.verify()['local_links'], 4)
        self.put('README.md', '[guide][not-defined]\n')
        self.assertIn('Undefined link reference', self.verify('failed')['issues'][0]['message'])

    def test_exact_case_is_required_for_each_component_on_every_platform(self):
        self.put('docs/Guides/Real.md', '# Real\n')
        for target in ('docs/guides/Real.md', 'docs/Guides/real.md'):
            with self.subTest(target=target):
                self.put('README.md', f'[guide]({target})\n')
                self.assertIn('case mismatch', self.verify('failed')['issues'][0]['message'])

    def test_nonportable_paths_and_encoded_repository_escape_fail(self):
        for target in ('C:/work/README.md', 'file:///tmp/README.md', '/README.md',
                       r'docs\guide.md', 'docs%5Cguide.md', '../outside.md', '%2e%2e/outside.md'):
            with self.subTest(target=target):
                self.put('README.md', f'[local]({target})\n')
                self.assertEqual(len(self.verify('failed')['issues']), 1)

    def test_external_links_are_skipped_including_queries_and_fragments(self):
        self.put('README.md', '[web](https://invalid.example/no-network#missing)\n'
                 '[mail](mailto:example@invalid.example)\n[protocol relative](//invalid.example/path)\n')
        report = self.verify()
        self.assertEqual(report['external_links_skipped'], 3)
        self.assertEqual(report['local_links'], 0)

    def test_symlink_cannot_read_or_validate_outside_the_checkout(self):
        outside = self.root.parent / 'outside.md'
        outside.write_text('# Outside\n', encoding='utf-8')
        link = self.root / 'docs/external.md'
        try:
            link.symlink_to(outside)
        except OSError:
            self.skipTest('Creating a symlink is not permitted on this host.')
        self.put('README.md', '[outside](docs/external.md#outside)\n')
        self.assertTrue(all('escapes the repository' in issue['message'] for issue in self.verify('failed')['issues']))

    def test_missing_maintained_root_file_is_a_failure(self):
        (self.root / 'AGENTS.md').unlink()
        self.assertEqual(self.verify('failed')['issues'][0]['file'], 'AGENTS.md')

    def test_cli_uses_explicit_root_from_another_directory_and_reports_failure_exit(self):
        script = Path(verify_docs.__file__).resolve()
        command = [sys.executable, str(script), '--root', str(self.root), '--json']
        result = subprocess.run(command, cwd=self.root.parent, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['root'], str(self.root))
        self.put('README.md', '[missing](gone.md)\n')
        result = subprocess.run(command, cwd=self.root.parent, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)['status'], 'failed')

    def test_requested_powershell_failure_is_honest_and_default_never_calls_it(self):
        self.put('README.md', '```powershell\nWrite-Output "example"\n```\n')
        with patch.object(verify_docs, 'powershell_issues', side_effect=ValueError('parser unavailable')) as parser:
            self.verify()
            parser.assert_not_called()
            report = self.verify('failed', powershell=True)
        self.assertEqual(report['powershell'], {'status': 'unavailable', 'blocks': 1})
        self.assertIn('parser unavailable', report['issues'][0]['message'])

    def test_powershell_is_explicitly_windows_only(self):
        with patch.object(verify_docs.os, 'name', 'posix'):
            with self.assertRaisesRegex(ValueError, 'requires Windows'):
                verify_docs.powershell_issues([])

    @unittest.skipUnless(os.name == 'nt' and (shutil.which('pwsh') or shutil.which('powershell')),
                         'Installed Windows PowerShell parser required.')
    def test_powershell_reports_syntax_location_without_executing_valid_examples(self):
        marker = self.root / 'must-not-be-created.txt'
        quoted = str(marker).replace("'", "''")
        self.put('README.md', f"# Main\n```powershell\nNew-Item -ItemType File -Path '{quoted}'\n```\n"
                 '```powershell\nif (\n```\n')
        report = self.verify('failed', powershell=True)
        self.assertFalse(marker.exists(), 'Parsing must never execute a documented command.')
        self.assertEqual(report['powershell'], {'status': 'failed', 'blocks': 2})
        self.assertTrue(all(issue['file'] == 'README.md' and issue['line'] == 6 for issue in report['issues']))


if __name__ == '__main__':
    unittest.main()
