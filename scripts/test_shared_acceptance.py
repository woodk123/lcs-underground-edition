"""Acceptance must reject stale/partial evidence and leave other servers alone."""
import copy
from argparse import Namespace
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from threading import Barrier, Lock
import unittest
from unittest.mock import patch

import shared_acceptance as acceptance


class AcceptanceTests(unittest.TestCase):
    def test_browser_workers_overlap_but_wait_for_validated_creation(self):
        rendezvous = Barrier(2, timeout=5)
        lock = Lock()
        active, peak = 0, 0
        finished = set()
        collected = []

        def execute(name):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
                if name == 'fresh-week':
                    self.assertIn('creation', finished)
            if name in ('creation', 'prepared-week'):
                rendezvous.wait()
            with lock:
                finished.add(name)
                active -= 1

        acceptance.run_browser_plan({'creation': (), 'fresh-week': ('creation',), 'prepared-week': ()},
                                    execute, 2, lambda name, error: collected.append((name, error)))
        self.assertEqual(peak, 2)
        self.assertEqual(finished, {'creation', 'fresh-week', 'prepared-week'})
        self.assertEqual(len(collected), 3)
        self.assertTrue(all(error is None for _, error in collected))

    def test_browser_failure_blocks_dependent_but_retains_independent_results(self):
        executed, collected = [], {}

        def execute(name):
            executed.append(name)
            if name == 'creation':
                raise ValueError('stale browser-loaded hash')

        with self.assertRaisesRegex(RuntimeError, 'creation.*fresh-week'):
            acceptance.run_browser_plan({'creation': (), 'fresh-week': ('creation',), 'personnel': ()},
                                        execute, 2, lambda name, error: collected.update({name: error}))
        self.assertCountEqual(executed, ['creation', 'personnel'])
        self.assertIsNone(collected['personnel'])
        self.assertIn('dependency', str(collected['fresh-week']))

    def test_one_browser_worker_is_sequential_and_invalid_limits_fail(self):
        executed = []
        plan = {'creation': (), 'fresh-week': ('creation',), 'personnel': ()}
        acceptance.run_browser_plan(plan, executed.append, 1, lambda *_: None)
        self.assertEqual(executed, list(plan))
        for workers in (0, 6):
            with self.assertRaisesRegex(ValueError, 'workers'):
                acceptance.run_browser_plan(plan, executed.append, workers, lambda *_: None)

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

    def test_serial_step_checkpoints_running_then_success_failure_or_timeout(self):
        for name, outcome in [('success', 0), ('failure', 7),
                              ('timeout', subprocess.TimeoutExpired(['synthetic-tool'], 1))]:
            with self.subTest(outcome=name):
                report = {'steps': []}
                path = self.root / f'{name}.json'
                def checkpoint():
                    acceptance.write_json(path, report)
                def process(command, **kwargs):
                    persisted = json.loads(path.read_text())
                    self.assertEqual(persisted['steps'][0]['status'], 'running')
                    self.assertEqual(persisted['steps'][0]['command'], command)
                    self.assertIn('started', persisted['steps'][0])
                    self.assertNotIn('completed', persisted['steps'][0])
                    if isinstance(outcome, Exception):
                        raise outcome
                    return subprocess.CompletedProcess(command, outcome)
                with patch.object(acceptance.subprocess, 'run', side_effect=process):
                    if isinstance(outcome, Exception):
                        with self.assertRaises(subprocess.TimeoutExpired) as failure:
                            acceptance.run_step(report, self.root, name, ['synthetic-tool'], self.root,
                                                checkpoint=checkpoint)
                        self.assertIs(failure.exception, outcome)
                    elif outcome:
                        with self.assertRaisesRegex(RuntimeError, 'failed'):
                            acceptance.run_step(report, self.root, name, ['synthetic-tool'], self.root,
                                                checkpoint=checkpoint)
                    else:
                        acceptance.run_step(report, self.root, name, ['synthetic-tool'], self.root,
                                            checkpoint=checkpoint)
                step = json.loads(path.read_text())['steps'][0]
                self.assertEqual(step['status'], 'passed' if outcome == 0 else 'failed')
                self.assertTrue({'started', 'completed', 'seconds'} <= step.keys())
                if not isinstance(outcome, Exception):
                    self.assertEqual(step['exit_code'], outcome)

    def test_worker_step_without_checkpoint_does_not_write_aggregate_report(self):
        path = self.root / 'report.json'
        original = '{"owner": "coordinator"}'
        path.write_text(original)
        worker = {'steps': []}
        with patch.object(acceptance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            acceptance.run_step(worker, self.root, 'browser-worker', ['synthetic-browser'], self.root)
        self.assertEqual(path.read_text(), original)
        self.assertEqual(worker['steps'][0]['status'], 'passed')

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


class AcceptancePreflightTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        suffix = '.bat' if os.name == 'nt' else ''
        self.flutter = self.root / f'.tools/flutter/bin/flutter{suffix}'
        self.dart = self.flutter.with_name(f'dart{suffix}')
        self.flutter.parent.mkdir(parents=True)
        self.flutter.write_text('SDK launcher fixture')
        self.dart.write_text('Dart launcher fixture')
        self.browser = self.root / 'upstream/tool/offline_test'
        self.browser.mkdir(parents=True)
        committed_browser = Path(acceptance.__file__).resolve().parent.parent / 'upstream/tool/offline_test'
        for name in ('package.json', 'package-lock.json'):
            (self.browser / name).write_bytes((committed_browser / name).read_bytes())
        browser_lock = json.loads((self.browser / 'package-lock.json').read_text())
        for name, package in browser_lock['packages'].items():
            if name and not package.get('optional'):
                installed = self.browser / name / 'package.json'
                installed.parent.mkdir(parents=True, exist_ok=True)
                acceptance.write_json(installed, {'version': package['version']})
        (self.root / 'scripts').mkdir()
        self.pin = {'flutter_version': '1.2.3', 'flutter_revision': 'a' * 40}
        (self.root / 'scripts/toolchain.json').write_text(json.dumps(self.pin))
        self.version = {'frameworkVersion': self.pin['flutter_version'],
                        'frameworkRevision': self.pin['flutter_revision']}
        self.web = self.root / '.local/supplied/web'
        self.web.mkdir(parents=True)
        for name in ('index.html', 'main.dart.js', 'sw.js'):
            (self.web / name).write_text(name)
        self.expected = acceptance.digest(self.web / 'main.dart.js')
        self.bootstrap = [str(self.flutter), '--suppress-analytics', '--version']
        self.host = patch.object(acceptance, 'ROOT', self.root)
        self.host.start()
        self.addCleanup(self.host.stop)
        node = patch.object(acceptance.shutil, 'which', return_value='node')
        node.start()
        self.addCleanup(node.stop)
        runtime = patch.object(acceptance, 'check_node', return_value='v22.19.0')
        self.node = runtime.start()
        self.addCleanup(runtime.stop)

    def args(self, name, **changes):
        return Namespace(**{'out': f'.local/{name}', 'web_root': None, 'expected_hash': None,
                            'port': 18879, 'personnel_port': 18882, 'browser_workers': 1,
                            'browser_executable': None, **changes})

    def report(self, args):
        return json.loads((self.root / args.out / 'report.json').read_text())

    def test_wrong_sdk_pin_fails_before_project_setup_or_port_reservation(self):
        for index, field in enumerate(('frameworkVersion', 'frameworkRevision')):
            args = self.args(f'wrong-pin-{index}')
            version = {**self.version, field: 'wrong'}
            with self.subTest(field=field), \
                    patch.object(acceptance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run, \
                    patch.object(acceptance.subprocess, 'check_output', return_value=json.dumps(version)), \
                    patch.object(acceptance, 'reserve_servers') as servers, \
                    patch.object(acceptance, 'run_browser_plan') as browsers:
                with self.assertRaisesRegex(ValueError, 'Flutter SDK does not match'):
                    acceptance.run(args)
                self.assertEqual([item.args[0] for item in run.call_args_list], [self.bootstrap])
                servers.assert_not_called()
                browsers.assert_not_called()
                report = self.report(args)
                self.assertEqual(report['status'], 'failed')
                self.assertEqual([step['name'] for step in report['steps']], ['sdk-bootstrap'])
                self.assertEqual(report['steps'][0]['status'], 'passed')

    def test_invalid_supplied_build_fails_before_sdk_project_or_browser_work(self):
        variants = [('absent-root', None), *[(name, name) for name in ('index.html', 'main.dart.js', 'sw.js')],
                    ('wrong-hash', None)]
        for index, (name, missing) in enumerate(variants):
            args = self.args(f'invalid-build-{index}',
                             web_root=str(self.root / 'absent') if name == 'absent-root' else str(self.web),
                             expected_hash='0' * 64 if name == 'wrong-hash' else self.expected)
            if missing:
                (self.web / missing).unlink()
            try:
                with self.subTest(build=name), \
                        patch.object(acceptance, 'run_step') as steps, \
                        patch.object(acceptance.subprocess, 'check_output', return_value=json.dumps(self.version)) as query, \
                        patch.object(acceptance, 'source_identity', return_value={}) as source, \
                        patch.object(acceptance, 'reserve_servers') as servers, \
                        patch.object(acceptance, 'run_browser_plan') as browsers:
                    with self.assertRaises((OSError, ValueError)):
                        acceptance.run(args)
                    steps.assert_not_called()
                    query.assert_not_called()
                    source.assert_not_called()
                    servers.assert_not_called()
                    browsers.assert_not_called()
                    self.node.assert_not_called()
                    report = self.report(args)
                    self.assertEqual(report['status'], 'failed')
                    self.assertEqual(report['steps'], [])
            finally:
                if missing:
                    (self.web / missing).write_text(missing)

    def test_missing_or_wrong_locked_browser_transitive_fails_before_sdk_and_ports(self):
        installed = self.browser / 'node_modules/playwright-core/package.json'
        original = installed.read_bytes()
        for index, corrupt in enumerate((None, {'version': 'wrong'})):
            self.node.reset_mock()
            if corrupt is None:
                installed.unlink()
                installed.parent.rmdir()
            else:
                acceptance.write_json(installed, corrupt)
            args = self.args(f'broken-browser-{index}')
            try:
                with self.subTest(corrupt=corrupt), \
                        patch.object(acceptance, 'run_step') as steps, \
                        patch.object(acceptance.subprocess, 'check_output') as sdk, \
                        patch.object(acceptance, 'reserve_servers') as servers, \
                        patch.object(acceptance, 'run_browser_plan') as browsers:
                    with self.assertRaisesRegex(ValueError, 'npm ci --prefix upstream/tool/offline_test'):
                        acceptance.run(args)
                    self.node.assert_called_once()
                    steps.assert_not_called()
                    sdk.assert_not_called()
                    servers.assert_not_called()
                    browsers.assert_not_called()
                    self.assertEqual(self.report(args)['steps'], [])
                    self.assertEqual(installed.is_file(), corrupt is not None)
                    if corrupt is not None:
                        self.assertEqual(json.loads(installed.read_text()), corrupt)
            finally:
                installed.parent.mkdir(parents=True, exist_ok=True)
                installed.write_bytes(original)

    def test_unsupported_node_fails_with_engine_remedy_before_sdk_and_ports(self):
        self.node.return_value = 'v0.0.0'
        args = self.args('old-node')
        with patch.object(acceptance, 'run_step') as steps, \
                patch.object(acceptance.subprocess, 'check_output') as sdk, \
                patch.object(acceptance, 'reserve_servers') as servers, \
                patch.object(acceptance, 'run_browser_plan') as browsers:
            with self.assertRaisesRegex(ValueError, 'Install Node.js') as failure:
                acceptance.run(args)
            self.assertIn('does not meet', str(failure.exception))
            steps.assert_not_called()
            sdk.assert_not_called()
            servers.assert_not_called()
            browsers.assert_not_called()
            self.assertEqual(self.report(args)['steps'], [])

    def test_cold_sdk_bootstraps_before_querying_structured_version(self):
        args = self.args('cold-sdk')
        self.assertFalse((self.flutter.parent / 'cache').exists())
        with patch.object(acceptance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run, \
                patch.object(acceptance.subprocess, 'check_output') as query, \
                patch.object(acceptance, 'reserve_servers', side_effect=RuntimeError('Reached project setup.')) as servers:
            def machine_version(command, **kwargs):
                self.assertEqual([item.args[0] for item in run.call_args_list], [self.bootstrap])
                self.assertEqual(command, [str(self.flutter), '--version', '--machine'])
                return json.dumps(self.version)
            query.side_effect = machine_version
            with self.assertRaisesRegex(RuntimeError, 'Reached project setup'):
                acceptance.run(args)
            servers.assert_called_once()
            report = self.report(args)
            self.assertEqual(report['toolchain'], self.pin)
            self.assertEqual([step['name'] for step in report['steps']], ['sdk-bootstrap'])
            self.assertTrue((self.root / args.out / 'sdk-bootstrap.log').is_file())

    def test_busy_port_after_valid_preflight_keeps_foreign_listener_and_releases_our_socket(self):
        with socket.socket() as foreign, socket.socket() as candidate:
            # Stay in the runner's dedicated QA range, away from fixed helper ports.
            for port in range(18999, 18882, -1):
                try:
                    foreign.bind(('127.0.0.1', port))
                    break
                except OSError:
                    continue
            else:
                self.skipTest('No free dedicated QA port for a foreign-listener fixture.')
            foreign.listen()
            occupied = foreign.getsockname()[1]
            for port in range(18999, 18882, -1):
                try:
                    candidate.bind(('127.0.0.1', port))
                    break
                except OSError:
                    continue
            else:
                self.skipTest('No second dedicated QA port for a reservation fixture.')
            free = candidate.getsockname()[1]
            candidate.close()
            args = self.args('busy-port', port=free, personnel_port=occupied)
            with patch.object(acceptance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run, \
                    patch.object(acceptance.subprocess, 'check_output', return_value=json.dumps(self.version)), \
                    patch.object(acceptance, 'run_browser_plan') as browsers:
                with self.assertRaisesRegex(OSError, 'unavailable'):
                    acceptance.run(args)
                self.assertEqual([item.args[0] for item in run.call_args_list], [self.bootstrap])
                browsers.assert_not_called()
            with socket.socket() as available:
                available.bind(('127.0.0.1', free))
            with socket.create_connection(('127.0.0.1', occupied), timeout=1):
                self.assertEqual(foreign.getsockname()[1], occupied)

    def test_supplied_payload_changed_during_project_setup_fails_before_browsers(self):
        args = self.args('changed-build', web_root=str(self.web), expected_hash=self.expected)
        source = {'commit': 'a' * 40, 'tree_sha256': 'b' * 64, 'working_tree': []}
        with patch.object(acceptance.subprocess, 'run') as run, \
                patch.object(acceptance.subprocess, 'check_output', return_value=json.dumps(self.version)), \
                patch.object(acceptance, 'source_identity', return_value=source), \
                patch.object(acceptance, 'reserve_servers'), \
                patch.object(acceptance, 'run_browser_plan') as browsers:
            def process(command, **kwargs):
                if command[1:3] == ['pub', 'get']:
                    (self.web / 'index.html').write_text('changed while dependencies were resolved')
                return subprocess.CompletedProcess(command, 0)
            run.side_effect = process
            with self.assertRaisesRegex(ValueError, 'Supplied web build changed during setup'):
                acceptance.run(args)
            browsers.assert_not_called()
            report = self.report(args)
            self.assertEqual(report['status'], 'failed')
            self.assertEqual([step['name'] for step in report['steps']],
                             ['sdk-bootstrap', 'dependencies', 'serialization', 'acceptance-tests'])

    def test_valid_supplied_build_preserves_journey_and_evidence_contracts(self):
        args = self.args('accepted-build', web_root=str(self.web), expected_hash=self.expected.upper())
        source = {'commit': 'a' * 40, 'tree_sha256': 'b' * 64, 'working_tree': []}
        browser_commands = []
        founder = b'{"declared":"synthetic exported founder"}'
        with patch.object(acceptance.subprocess, 'run') as run, \
                patch.object(acceptance.subprocess, 'check_output', return_value=json.dumps(self.version)), \
                patch.object(acceptance, 'source_identity', return_value=source), \
                patch.object(acceptance, 'reserve_servers'):
            def process(command, **kwargs):
                persisted = self.report(args)
                if command[0] != 'node':
                    self.assertEqual(persisted['steps'][-1]['status'], 'running')
                    self.assertEqual(persisted['steps'][-1]['command'], command)
                else:
                    self.assertTrue(all(step['status'] != 'running' for step in persisted['steps']),
                                    'Workers must not checkpoint their partial report over the aggregate.')
                if command[0] == 'node':
                    browser_commands.append(command)
                    output = Path(command[command.index('--out') + 1])
                    output.mkdir(parents=True)
                    if output.name == 'creation':
                        (output / 'manual-founder.json').write_bytes(founder)
                    elif output.name == 'fresh-week':
                        imported = Path(command[command.index('--campaign') + 1])
                        self.assertEqual(imported, output.parent / 'creation/manual-founder.json')
                        self.assertEqual(imported.read_bytes(), founder)
                    elif output.name == 'prepared-week':
                        self.assertNotIn('--campaign', command)
                    acceptance.write_json(output / 'report.json', {
                        'status': 'passed', 'mainJsSha256': self.expected,
                        'loadedMainJsHashes': [self.expected], 'checks': ['synthetic contract check'],
                        'pageErrors': [], 'consoleErrors': [], 'failedRequests': [],
                        'scope': 'Synthetic report for acceptance coordinator contract tests.',
                    })
                return subprocess.CompletedProcess(command, 0)
            run.side_effect = process
            self.assertEqual(acceptance.run(args), self.root / args.out / 'report.json')
        report = self.report(args)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['schema'], 1)
        self.assertEqual(report['toolchain'], self.pin)
        self.assertEqual(report['source'], source)
        self.assertEqual(report['test_files'], list(acceptance.TESTS))
        self.assertEqual(report['build']['origin'], 'supplied artifact')
        self.assertEqual(report['build']['main_js_sha256'], self.expected)
        self.assertEqual(json.loads((self.root / args.out / 'web-hashes.json').read_text()),
                         acceptance.file_hashes(self.web))
        expected_steps = ['sdk-bootstrap', 'dependencies', 'serialization', 'acceptance-tests',
                          'creation', 'fresh-week', 'prepared-week', 'organisation', 'keyboard-interface', 'personnel']
        self.assertEqual([step['name'] for step in report['steps']], expected_steps)
        self.assertTrue(all(step['status'] == 'passed' and step['exit_code'] == 0
                            and {'log', 'seconds', 'started', 'completed'} <= step.keys() for step in report['steps']))
        self.assertEqual([suite['name'] for suite in report['browser_suites']], expected_steps[4:])
        self.assertEqual(len(browser_commands), 6)


if __name__ == '__main__':
    unittest.main()
