"""Acceptance must reject stale/partial evidence and leave other servers alone."""
import copy
from argparse import Namespace
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import shared_acceptance as acceptance


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.expected = 'a' * 64
        self.path = self.root / 'report.json'
        self.valid = {'status': 'passed', 'mainJsSha256': self.expected,
                      'loadedMainJsHashes': [self.expected, self.expected],
                      'checks': ['real journey', {'name': 'save continuity', 'status': 'passed'}],
                      'pageErrors': [], 'consoleErrors': [], 'failedRequests': []}

    def check_report(self, report):
        self.path.write_text(json.dumps(report), encoding='utf-8')
        return acceptance.validate_browser_report(self.path, self.expected)

    def test_accepts_matching_loaded_build_and_complete_checks(self):
        self.assertEqual(self.check_report(self.valid), self.valid)

    def test_rejects_partial_stale_skipped_or_erroring_reports(self):
        for key, value in [
            ('status', 'running'), ('status', 'failed'), ('mainJsSha256', 'b' * 64),
            ('loadedMainJsHashes', []), ('loadedMainJsHashes', ['b' * 64]),
            ('checks', []), ('checks', [{'name': 'not run', 'status': 'skipped'}]),
            ('pageErrors', ['exception']), ('consoleErrors', ['bad image']),
            ('failedRequests', ['missing.webp']), ('failedRequests', None),
        ]:
            with self.subTest(key=key, value=value):
                report = copy.deepcopy(self.valid)
                report[key] = value
                with self.assertRaises(ValueError):
                    self.check_report(report)

    def test_failed_process_retains_log_and_cannot_mark_step_passed(self):
        report = {'steps': []}
        with self.assertRaisesRegex(RuntimeError, 'failed'):
            acceptance.run_step(report, self.root, 'failure',
                                [sys.executable, '-c', 'print("failure evidence"); raise SystemExit(7)'], self.root)
        self.assertEqual(report['steps'][0]['status'], 'failed')
        self.assertEqual(report['steps'][0]['exit_code'], 7)
        self.assertIn('failure evidence', (self.root / 'failure.log').read_text())

    def test_output_never_replaces_source_or_existing_evidence(self):
        for path in [str(self.root), str(self.root / 'upstream'), str(self.root / '.local')]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                acceptance.output_directory(self.root, path)
        result = acceptance.output_directory(self.root, '.local/reports/acceptance')
        self.assertTrue(result.is_dir())
        with self.assertRaises(FileExistsError):
            acceptance.output_directory(self.root, str(result))

    def test_busy_port_does_not_replace_server_and_releases_earlier_reservation(self):
        with socket.socket() as foreign:
            foreign.bind(('127.0.0.1', 0))
            foreign.listen()
            occupied = foreign.getsockname()[1]
            with socket.socket() as temporary:
                temporary.bind(('127.0.0.1', 0))
                free = temporary.getsockname()[1]
            with self.assertRaises(OSError):
                acceptance.reserve_servers(self.root, (free, occupied))
            # Failure releases only our earlier socket; the foreign listener lives.
            with socket.socket() as available:
                available.bind(('127.0.0.1', free))
            with socket.socket() as still_occupied, self.assertRaises(OSError):
                still_occupied.bind(('127.0.0.1', occupied))
            self.assertEqual(foreign.getsockname()[1], occupied)

    def test_source_identity_detects_uncommitted_untracked_and_missing_inputs(self):
        def git(*args):
            return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git('init', '-q')
        path = self.root / 'game.dart'
        path.write_text('original')
        git('add', 'game.dart')
        git('-c', 'user.name=Acceptance Test', '-c', 'user.email=acceptance@example.invalid',
            'commit', '-qm', 'fixture')
        original = acceptance.source_identity(self.root)
        path.write_text('changed')
        changed = acceptance.source_identity(self.root)
        self.assertNotEqual(changed['tree_sha256'], original['tree_sha256'])
        path.write_text('original')
        extra = self.root / 'new.dart'
        extra.write_text('new code')
        self.assertNotEqual(acceptance.source_identity(self.root)['tree_sha256'], original['tree_sha256'])
        extra.unlink()
        path.unlink()
        self.assertNotEqual(acceptance.source_identity(self.root)['tree_sha256'], original['tree_sha256'])
        self.assertEqual(changed['commit'], original['commit'])

    def test_rejects_an_existing_http_server_even_when_it_allows_address_reuse(self):
        foreign = acceptance.GameServer(('127.0.0.1', 0), acceptance.AcceptanceHandler)
        self.addCleanup(foreign.server_close)
        with self.assertRaises(OSError):
            with acceptance.reserve_servers(self.root, (foreign.server_port,)):
                pass

    def test_runner_rejects_player_out_of_range_and_duplicate_ports_before_work(self):
        for i, ports in enumerate([(8765, 18882), (18889, 18889), (19000, 18882), (18879, 18878)]):
            args = Namespace(out=f'.local/ports-{i}', web_root=None, expected_hash=None,
                             port=ports[0], personnel_port=ports[1], browser_executable=None)
            with self.subTest(ports=ports), patch.object(acceptance, 'ROOT', self.root):
                with self.assertRaisesRegex(ValueError, 'two different dedicated QA ports'):
                    acceptance.run(args)
                report = json.loads((self.root / args.out / 'report.json').read_text())
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(report['steps'], [])


if __name__ == '__main__':
    unittest.main()
