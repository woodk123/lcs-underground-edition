"""Run the shared opening-week acceptance checks against one isolated web build."""
from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from contextlib import ExitStack
from datetime import datetime, timezone
from functools import partial
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
from threading import Thread
import time
from urllib.request import urlopen

from release_common import digest, file_hashes, write_json
from serve import GameHandler, GameServer


ROOT = Path(__file__).resolve().parent.parent
TESTS = (
    'creation_flow_test.dart', 'creation_bonus_help_test.dart',
    'organisation_journal_test.dart', 'journal_navigation_state_test.dart', 'page_storage_isolation_test.dart',
    'network_journal_test.dart', 'personnel_directory_test.dart',
    'save_load_test.dart', 'save_round_trip_test.dart', 'save_recovery_test.dart',
    'operation_history_test.dart', 'crew_operation_history_test.dart',
    'keyboard_orders_workspace_test.dart', 'keyboard_reader_choices_test.dart',
    'character_presentation_test.dart', 'classic_status_display_test.dart', 'journal_preferences_test.dart',
    'keyboard_navigation_test.dart', 'text_prompt_focus_test.dart',
    'classic_keyboard_parity_test.dart', 'classic_ledger_keyboard_parity_test.dart',
    'classic_base_keyboard_parity_test.dart', 'classic_menu_labels_test.dart',
    'base_management_controller_test.dart', 'journal_ledger_test.dart',
    'journal_media_test.dart', 'journal_agenda_test.dart',
    'legislation_presentation_test.dart', 'article_view_test.dart',
)
PORTS = (18879, 18882)  # Existing helpers deliberately pin these QA origins.


def source_identity(root: Path) -> dict:
    commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    paths = subprocess.check_output([
        'git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
    ]).decode('utf-8').split('\0')
    tree = hashlib.sha256()
    for name in sorted(set(paths) - {''}):
        path = root / name
        value = digest(path) if path.is_file() else 'missing'
        tree.update(f'{name}\0{value}\0'.encode('utf-8'))
    return {'commit': commit, 'tree_sha256': tree.hexdigest(), 'working_tree': subprocess.check_output(
        ['git', '-C', str(root), 'status', '--porcelain=v1'], text=True).splitlines()}


def output_directory(root: Path, value: str) -> Path:
    output = (root / value).resolve()
    if not any(output.is_relative_to(root / parent) and output != root / parent
               for parent in ('.local', 'reports')):
        raise ValueError('Acceptance output must be a new directory under .local/ or reports/.')
    output.mkdir(parents=True, exist_ok=False)
    return output


def run_step(report: dict, output: Path, name: str, command: list[str], cwd: Path, *, env=None) -> None:
    print(f'RUN {name}', flush=True)
    step = {'name': name, 'command': command, 'log': f'{name}.log', 'status': 'running'}
    step['started'] = datetime.now(timezone.utc).isoformat()
    report['steps'].append(step)
    started = time.monotonic()
    try:
        with (output / step['log']).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=1800, check=False)
        step['exit_code'] = result.returncode
        if result.returncode:
            raise RuntimeError(f'{name} failed ({result.returncode}); see {output / step["log"]}')
        step['status'] = 'passed'
    except BaseException:
        step['status'] = 'failed'
        raise
    finally:
        step['seconds'] = round(time.monotonic() - started, 3)
        step['completed'] = datetime.now(timezone.utc).isoformat()


def run_browser_plan(dependencies, execute, workers, completed):
    """Bound concurrency; only validated success unlocks dependent journeys.

    The coordinator alone calls completed(), so aggregate evidence is never
    written by competing browser threads. Independent failures are collected;
    their dependents are blocked while already-running browsers finish cleanup.
    """
    if not 1 <= workers <= 5:
        raise ValueError('Browser workers must be between 1 and 5.')
    pending = dict(dependencies)
    if any(set(required) - pending.keys() for required in pending.values()):
        raise ValueError('Unknown browser dependency.')
    passed, failures = set(), {}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        running = {}
        while pending or running:
            for name, required in list(pending.items()):
                if any(parent in failures for parent in required):
                    error = RuntimeError(f'{name} blocked by a failed browser dependency.')
                    failures[name] = error
                    del pending[name]
                    completed(name, error)
                elif len(running) < workers and set(required) <= passed:
                    running[pool.submit(execute, name)] = name
                    del pending[name]
            if not running:
                if pending:
                    raise ValueError('Cyclic browser dependencies.')
                break
            finished, _ = wait(running, return_when=FIRST_COMPLETED)
            for future in finished:
                name = running.pop(future)
                error = future.exception()
                if error is None:
                    passed.add(name)
                else:
                    failures[name] = error
                completed(name, error)
    if failures:
        names = ', '.join(failures)
        raise RuntimeError(f'Browser acceptance failed: {names}. See per-stage logs and reports.') from next(iter(failures.values()))


def validate_browser_report(path: Path, expected_hash: str) -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('status') != 'passed' or data.get('mainJsSha256') != expected_hash:
        raise ValueError(f'Browser report did not accept the requested build: {path}')
    checks = data.get('checks')
    if not isinstance(checks, list) or not checks or any(
            not check or isinstance(check, dict) and check.get('status') != 'passed' for check in checks):
        raise ValueError(f'Browser report has missing, skipped or failed checks: {path}')
    hashes = data.get('loadedMainJsHashes')
    if not hashes or any(value != expected_hash for value in hashes):
        raise ValueError(f'Browser did not load the requested JavaScript: {path}')
    for key in ('pageErrors', 'consoleErrors', 'failedRequests'):
        if data.get(key) != []:
            raise ValueError(f'Browser report contains {key}: {path}')
    return data


class AcceptanceHandler(GameHandler):
    def log_message(self, format, *args):
        # Browser/network failures are retained in each helper's report.
        pass


class AcceptanceServer(GameServer):
    # Windows SO_REUSEADDR permits a second listener to steal requests from a
    # running Python HTTP server. POSIX reuse only allows normal restart here.
    allow_reuse_address = os.name != 'nt'

    def server_bind(self):
        if os.name == 'nt':
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def reserve_servers(web: Path, ports=PORTS) -> ExitStack:
    """Bind our own sockets; never reuse or stop an existing QA/player server."""
    stack = ExitStack()
    try:
        servers = []
        for port in ports:
            try:
                server = AcceptanceServer(('127.0.0.1', port), partial(AcceptanceHandler, directory=str(web)))
            except OSError as error:
                raise OSError(f'QA port {port} is unavailable; acceptance must own this origin.') from error
            stack.callback(server.server_close)
            servers.append(server)
        stack.servers = servers
        return stack
    except BaseException:
        stack.close()
        raise


def run(args) -> Path:
    output = output_directory(ROOT, args.out)
    report = {'schema': 1, 'status': 'running', 'started': datetime.now(timezone.utc).isoformat(),
              'scope': 'Fresh creation → unchanged founder → seven actual days → exact save transfer; '
                       'prepared recruitment/equipment and mixed-status personnel branches are separate.',
              'steps': [], 'browser_suites': []}
    report_path = output / 'report.json'
    write_json(report_path, report)
    try:
        supplied = args.web_root is not None
        if supplied != bool(args.expected_hash):
            raise ValueError('--web-root and --expected-hash must be supplied together.')
        if supplied and not re.fullmatch('[a-fA-F0-9]{64}', args.expected_hash):
            raise ValueError('--expected-hash must be a complete SHA-256.')
        ports = (args.port, args.personnel_port)
        if len(set(ports)) != 2 or any(not 18879 <= port <= 18999 for port in ports):
            raise ValueError('Choose two different dedicated QA ports between 18879 and 18999.')
        workers = args.browser_workers
        if not 1 <= workers <= 5:
            raise ValueError('Browser workers must be between 1 and 5.')
        report['browser_workers'] = workers
        report['origins'] = [f'http://127.0.0.1:{port}/' for port in ports]
        web = (ROOT / args.web_root).resolve(strict=True) if supplied else output / 'web'
        suffix = '.bat' if os.name == 'nt' else ''
        flutter = ROOT / f'.tools/flutter/bin/flutter{suffix}'
        dart = ROOT / f'.tools/flutter/bin/dart{suffix}'
        node = shutil.which('node')
        if not flutter.is_file() or not dart.is_file() or not node:
            raise ValueError('Install the pinned Flutter SDK and Node.js; see docs/BUILDING.md.')
        if not (ROOT / 'upstream/tool/offline_test/node_modules/playwright').is_dir():
            raise ValueError('Install locked browser dependencies: npm ci --prefix upstream/tool/offline_test')
        with reserve_servers(web, ports) as owned:
            run_step(report, output, 'dependencies', [str(flutter), 'pub', 'get'], ROOT / 'upstream')
            run_step(report, output, 'serialization', [str(dart), 'run', 'build_runner', 'build'], ROOT / 'upstream')
            version = json.loads(subprocess.check_output([str(flutter), '--version', '--machine'], text=True))
            pin = json.loads((ROOT / 'scripts/toolchain.json').read_text())
            if version['frameworkVersion'] != pin['flutter_version'] or version['frameworkRevision'] != pin['flutter_revision']:
                raise ValueError('Flutter SDK does not match scripts/toolchain.json.')
            report['toolchain'] = pin
            report['source'] = source_identity(ROOT)
            run_step(report, output, 'acceptance-tests', [str(flutter), 'test', '--no-pub',
                     '--reporter', 'expanded', *[f'test/{name}' for name in TESTS]], ROOT / 'upstream')
            report['test_files'] = list(TESTS)
            if not supplied:
                run_step(report, output, 'web-build', [str(flutter), 'build', 'web', '--release',
                         '--no-pub', '--no-wasm-dry-run', f'--output={web}',
                         f'--dart-define=LCS_BUILD={report["source"]["commit"][:8]}',
                         '--dart-define=LCS_CHANNEL=Development'], ROOT / 'upstream')
                run_step(report, output, 'offline-manifest', [str(dart), 'run',
                         'tool/inject_service_worker.dart', str(web)], ROOT / 'upstream')
            for name in ('index.html', 'main.dart.js', 'sw.js'):
                if not (web / name).is_file():
                    raise ValueError(f'Incomplete web build: {name}')
            expected = digest(web / 'main.dart.js')
            if supplied and expected != args.expected_hash.lower():
                raise ValueError('Supplied web build does not match --expected-hash.')
            payload = file_hashes(web)
            write_json(output / 'web-hashes.json', payload)
            report['build'] = {'directory': str(web), 'main_js_sha256': expected,
                               'origin': 'supplied artifact' if supplied else 'built by this run',
                               'hash_manifest': 'web-hashes.json'}
            for server in owned.servers:
                Thread(target=server.serve_forever, daemon=True).start()
                owned.callback(server.shutdown)
                url = f'http://127.0.0.1:{server.server_port}/'
                with urlopen(url + '__lcs_launcher_health', timeout=5) as response:
                    health = json.load(response)
                if health != {'application': 'lcs-modern-local', 'directory': str(web)}:
                    raise ValueError(f'Unexpected launcher health at {url}')
                with urlopen(url + 'main.dart.js', timeout=15) as response:
                    if hashlib.sha256(response.read()).hexdigest() != expected:
                        raise ValueError(f'Wrong served build at {url}')
            suites = [
                ('creation', 'creation_browser_review.mjs', []),
                ('fresh-week', 'first_week_browser_review.mjs',
                 ['--campaign', str(output / 'creation/manual-founder.json')]),
                ('prepared-week', 'first_week_browser_review.mjs', []),
                ('organisation', 'browser_review.mjs', []),
                ('keyboard-interface', 'keyboard_interface_browser_review.mjs', []),
                ('personnel', 'personnel_browser_review.mjs', []),
            ]
            suite_map = {name: (helper, extra) for name, helper, extra in suites}
            results = {name: {'steps': []} for name in suite_map}
            setup_steps = list(report['steps'])
            browser_started = time.monotonic()

            def execute(name):
                helper, extra = suite_map[name]
                qa_url = report['origins'][1 if name == 'personnel' else 0]
                command = [node, str(ROOT / 'scripts' / helper), '--expected-hash', expected,
                           '--url', qa_url, '--out', str(output / name), *extra]
                if args.browser_executable:
                    command.extend(['--browser-executable', args.browser_executable])
                run_step(results[name], output, name, command, ROOT,
                         env={**os.environ, 'LCS_ACCEPTANCE_QA_URL': qa_url})
                data = validate_browser_report(output / name / 'report.json', expected)
                results[name]['suite'] = {'name': name, 'report': f'{name}/report.json',
                                         'scope': data['scope'], 'checks': len(data['checks']),
                                         'days': len(data.get('days', []))}

            def completed(name, error):
                result = results[name]
                if error is not None:
                    if not result['steps']:
                        result['steps'].append({'name': name, 'status': 'blocked', 'seconds': 0})
                    result['steps'][-1].update(status='failed' if result['steps'][-1]['status'] != 'blocked'
                                              else 'blocked', error=str(error))
                # Copy only completed results; running threads own their evidence.
                result['collected'] = True
                report['steps'] = setup_steps + [step for key in suite_map if results[key].get('collected')
                                                 for step in results[key]['steps']]
                report['browser_suites'] = [results[key]['suite'] for key in suite_map
                                           if results[key].get('collected') and 'suite' in results[key]]
                report['browser_seconds'] = round(time.monotonic() - browser_started, 3)
                write_json(report_path, report)

            run_browser_plan({name: ('creation',) if name == 'fresh-week' else () for name in suite_map},
                             execute, workers, completed)
            if source_identity(ROOT) != report['source'] or file_hashes(web) != payload:
                raise ValueError('Source or compiled build changed during acceptance. Rerun on settled input.')
        report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report['completed'] = datetime.now(timezone.utc).isoformat()
        write_json(report_path, report)
        print(f'{report["status"].upper()}: {report_path}', flush=True)
    return report_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
    parser.add_argument('--out', default=f'.local/reports/shared-acceptance-{stamp}')
    parser.add_argument('--web-root', help='Reuse an existing build with its required --expected-hash.')
    parser.add_argument('--expected-hash')
    parser.add_argument('--browser-executable', help='Optional path to an installed Chromium browser.')
    parser.add_argument('--browser-workers', type=int, default=4,
                        help='Concurrent isolated browser journeys, 1–5 (default: 4; 1 is sequential).')
    parser.add_argument('--port', type=int, default=PORTS[0], help='Dedicated QA port (18879–18999).')
    parser.add_argument('--personnel-port', type=int, default=PORTS[1], help='Separate personnel QA port.')
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
