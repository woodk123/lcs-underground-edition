"""Independent CI check shards/builds and strict evidence validation for releases."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from package_release import vc_runtime, verify_source_checkout
from ci_shards import SHARDS, test_files
from release_common import WINDOWS_RUNTIME_FILES, digest, file_hashes, require_files, runtime_hashes, safe_relative, write_json

PLATFORMS = ('linux', 'windows')
BUILD_TARGETS = ('linux', 'windows', 'web')
BUILD_OUTPUTS = {
    'linux': {'bundle': 'linux/x64/release/bundle'},
    'windows': {'native': 'windows/x64/runner/Release'},
    'web': {'web': 'web'},
}
FOCUSED = ['lib/modern', 'lib/main.dart', 'lib/engine/console.dart',
           'lib/engine/console_widget.dart', 'lib/engine/console_char.dart', 'lib/engine/console_graphic.dart']


def identity(root: Path) -> dict:
    return {'source_commit': subprocess.check_output(
        ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
        'toolchain': json.loads((root / 'scripts/toolchain.json').read_text())}


def required_steps(kind: str, target: str, shard: int = 0) -> list[str]:
    common = ['dependencies', 'serialization']
    if kind == 'checks':
        return common + ['tests'] + (['tooling', 'assets', 'focused-analysis', 'full-analysis'] if shard == 0 else [])
    return common + {'linux': ['linux-release'], 'windows': ['windows-release'],
                     'web': ['web-release', 'offline-manifest']}[target]


def run_worker(root: Path, kind: str, target: str, shard: int) -> None:
    host = platform.system().lower()
    if host != ('linux' if target == 'web' else target) or (kind == 'checks' and target not in PLATFORMS):
        raise ValueError('Worker platform does not match this host.')
    info = {'schema': 1, **identity(root), 'kind': kind, 'platform': target,
            'shard': shard if kind == 'checks' else None, 'shards': SHARDS,
            'run_id': os.environ.get('GITHUB_RUN_ID'), 'status': 'running', 'steps': [],
            'codegen_cache_hit': os.environ.get('CI_CODEGEN_CACHE_HIT') == 'true',
            'sdk_cache_hit': os.environ.get('CI_SDK_CACHE_HIT') == 'true',
            'sdk_target': os.environ.get('CI_SDK_TARGET'),
            'test_compiler_cache_hit': os.environ.get('CI_TEST_CACHE_HIT') == 'true',
            'host_platform': host}
    verify_source_checkout(root, info['source_commit'])
    suffix = '.bat' if host == 'windows' else ''
    flutter = str(root / f'.tools/flutter/bin/flutter{suffix}')
    dart = str(root / f'.tools/flutter/bin/dart{suffix}')
    sdk = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    if (sdk['frameworkRevision'] != info['toolchain']['flutter_revision'] or
            sdk['frameworkVersion'] != info['toolchain']['flutter_version']):
        raise ValueError('Flutter SDK does not match the pinned toolchain.')
    name = f'checks-{target}-{shard}' if kind == 'checks' else f'build-{target}'
    output = root / '.local/ci' / name
    output.mkdir(parents=True, exist_ok=False)
    commands = [
        ('dependencies', [flutter, 'pub', 'get'], root / 'upstream'),
        ('serialization', [dart, 'run', 'build_runner', 'build'], root / 'upstream'),
    ]
    if kind == 'checks':
        info['test_files'] = test_files(root, shard, target)
        if not info['test_files']:
            raise ValueError('Test shard is empty.')
        commands.append(('tests', [flutter, 'test', '--no-pub',
                                  f'--file-reporter=json:../.local/ci/{name}/tests.jsonl',
                                  *info['test_files']], root / 'upstream'))
        if shard == 0:
            commands.extend([
                ('tooling', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts', '-p', 'test_*.py', '-v'], root),
                ('assets', [sys.executable, 'scripts/verify_assets.py'], root),
                ('focused-analysis', [flutter, 'analyze', '--no-pub', *FOCUSED], root / 'upstream'),
                ('full-analysis', [flutter, 'analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings'], root / 'upstream'),
            ])
    else:
        define = f"--dart-define=LCS_BUILD={info['source_commit'][:8]}"
        info['channel'] = os.environ.get('LCS_CHANNEL', 'Nightly')
        if info['channel'] not in ('Nightly', 'Preview', 'Release'):
            raise ValueError('Invalid CI player channel.')
        channel = f"--dart-define=LCS_CHANNEL={info['channel']}"
        if target == 'linux':
            commands.append(('linux-release', [flutter, 'build', 'linux', '--release', '--no-pub', define, channel], root / 'upstream'))
        elif target == 'windows':
            commands.append(('windows-release', [flutter, 'build', 'windows', '--release', '--no-pub', define, channel], root / 'upstream'))
        else:
            commands.extend([
                ('web-release', [flutter, 'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--base-href', '/', define, channel], root / 'upstream'),
                ('offline-manifest', [dart, 'run', 'tool/inject_service_worker.dart', 'build/web'], root / 'upstream'),
            ])
    try:
        for step, command, cwd in commands:
            print(f'[{step}]', flush=True)
            started = time.monotonic()
            with (output / f'{step}.log').open('w', encoding='utf-8') as log:
                process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
                for line in process.stdout:
                    print(line, end='', flush=True)
                    log.write(line)
                code = process.wait()
            info['steps'].append({'name': step, 'exit_code': code,
                                  'elapsed_seconds': round(time.monotonic() - started, 2)})
            if code:
                raise ValueError(f'{step} failed with exit {code}.')
        verify_source_checkout(root, info['source_commit'])
        generated = {p.relative_to(root / 'upstream').as_posix(): digest(p)
                     for p in sorted((root / 'upstream/lib').rglob('*.g.dart'))}
        if not generated:
            raise ValueError('Generated serialization source is missing.')
        info['generated_hashes'] = generated
        if kind == 'build':
            for relative in generated:
                destination = output / 'generated' / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / 'upstream' / relative, destination)
            locations = BUILD_OUTPUTS[target]
            for folder, built in locations.items():
                shutil.copytree(root / 'upstream/build' / built, output / folder)
            if target == 'windows':
                # Discover redistributables on the machine that compiled the
                # player, so any publisher host can seal the complete runtime.
                runtime = vc_runtime()
                require_files(runtime, WINDOWS_RUNTIME_FILES)
                for filename in WINDOWS_RUNTIME_FILES:
                    shutil.copyfile(runtime / filename, output / 'native' / filename)
                shutil.copyfile(root / '.tools/flutter/LICENSE', output / 'Flutter-LICENSE.txt')
                info['flutter_license_hash'] = digest(output / 'Flutter-LICENSE.txt')
            info['payload_hashes'] = {folder: file_hashes(output / folder) for folder in locations}
        info['status'] = 'passed'
    except Exception:
        info['status'] = 'failed'
        raise
    finally:
        write_json(output / 'report.json', info)


def verify_evidence(root: Path, artifacts: Path) -> dict[str, dict]:
    expected = identity(root)
    reports = {}
    run_ids = set()
    for target in BUILD_TARGETS:
        workers = (('checks', range(SHARDS)), ('build', [0])) if target in PLATFORMS else (('build', [0]),)
        for kind, shards in workers:
            for shard in shards:
                name = f'checks-{target}-{shard}' if kind == 'checks' else f'build-{target}'
                info = json.loads((artifacts / name / 'report.json').read_text(encoding='utf-8'))
                if (info.get('schema') != 1 or info.get('status') != 'passed' or
                        any(info.get(k) != v for k, v in expected.items()) or
                        info.get('kind') != kind or info.get('platform') != target or
                        info.get('host_platform') != ('linux' if target == 'web' else target) or
                        info.get('shards') != SHARDS or
                        info.get('shard') != (shard if kind == 'checks' else None) or
                        [s['name'] for s in info['steps']] != required_steps(kind, target, shard) or
                        any(s['exit_code'] != 0 for s in info['steps'])):
                    raise ValueError(f'Invalid or mismatched CI evidence: {name}')
                if not str(info.get('run_id') or '').isdigit():
                    raise ValueError('CI evidence must identify its Actions run.')
                run_ids.add(str(info['run_id']))
                expected_run = os.environ.get('CI_ARTIFACT_RUN_ID')
                if expected_run and str(info['run_id']) != expected_run:
                    raise ValueError('CI artifact run does not match the selected run.')
                if kind == 'checks' and info.get('test_files') != test_files(root, shard, target):
                    raise ValueError(f'Test shard inventory differs: {name}')
                if kind == 'build':
                    channel = info.get('channel', 'Nightly')
                    if channel not in ('Nightly', 'Preview', 'Release') or channel != os.environ.get('LCS_CHANNEL', 'Nightly'):
                        raise ValueError(f'CI player channel differs from the requested release: {name}')
                    if info.get('generated_hashes') != file_hashes(artifacts / name / 'generated'):
                        raise ValueError('Generated source differs from the build artifact.')
                    folders = BUILD_OUTPUTS[target]
                    if target == 'linux':
                        runtime_hashes(artifacts / name / 'bundle', 'linux-x64')
                    elif target == 'windows':
                        if info.get('flutter_license_hash') != digest(artifacts / name / 'Flutter-LICENSE.txt'):
                            raise ValueError('Flutter license differs from the build artifact.')
                        runtime_hashes(artifacts / name / 'native', 'windows-x64')
                    else:
                        require_files(artifacts / name / 'web', ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'))
                        if 'const RESOURCES = null; // build: manifest' in (artifacts / name / 'web/sw.js').read_text(encoding='utf-8'):
                            raise ValueError('CI web offline manifest was not injected.')
                    actual = {folder: file_hashes(artifacts / name / folder) for folder in folders}
                    if info.get('payload_hashes') != actual:
                        raise ValueError(f'CI build file hashes differ: {name}')
                reports[name] = info
    if len(run_ids) != 1:
        raise ValueError('All artifacts must come from the same Actions run.')
    generated = reports['build-windows'].get('generated_hashes')
    if (not generated or any(not name.startswith('lib/') or not name.endswith('.g.dart')
                             or safe_relative(name) != name for name in generated)):
        raise ValueError('Generated source inventory is invalid.')
    if any(info.get('generated_hashes') != generated for info in reports.values()):
        raise ValueError('Checks and builds used different generated source.')
    return reports


def prepare_release(root: Path, artifacts: Path) -> Path:
    """Validate every shard/build before adapting evidence for the local packager."""
    reports = verify_evidence(root, artifacts)
    expected = identity(root)
    verify_source_checkout(root, expected['source_commit'])
    report = root / '.local/reports/ci-release'
    report.mkdir(parents=True, exist_ok=False)
    for name in reports:
        shutil.copytree(artifacts / name, report / 'ci' / name,
                        ignore=shutil.ignore_patterns('bundle', 'web', 'native', 'generated'))
    for relative in reports['build-windows']['generated_hashes']:
        destination = root / 'upstream' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(artifacts / 'build-windows/generated' / relative, destination)
    for target, folder, destination in [('web', 'web', 'web'), ('windows', 'native', 'windows/x64/runner/Release')]:
        shutil.copytree(artifacts / f'build-{target}' / folder, root / 'upstream/build' / destination)
    license_path = root / '.tools/flutter/LICENSE'
    license_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifacts / 'build-windows/Flutter-LICENSE.txt', license_path)
    linux = root / '.local/linux'
    shutil.copytree(artifacts / 'build-linux' / 'bundle', linux / 'bundle')
    linux_info = {**expected, 'status': 'passed', 'steps': [
        {'name': name, 'exit_code': 0} for name in
        ['dependencies', 'serialization', 'tests', 'focused-analysis', 'full-analysis', 'linux-release']],
        'bundle_hashes': reports['build-linux']['payload_hashes']['bundle']}
    write_json(linux / 'evidence/build-info.json', linux_info)
    info = {**expected, 'status': 'automated_checks_passed_manual_qa_pending', 'ci_evidence': True,
            'steps': [{'name': name, 'exit_code': 0} for name in
                      ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                       '05-full-analysis', '06-web-release', '07-offline-manifest', '08-windows-release']]}
    write_json(report / 'build-info.json', info)
    return report


def verify_packaging_evidence(root: Path, report: Path, linux: Path | None) -> None:
    """Revalidate original evidence against the actual payloads at packaging time."""
    if linux is None:
        raise ValueError('CI release requires the checked Linux payload.')
    # Reports are retained separately from large payloads; validate through a
    # temporary layout rather than duplicating build files in the source ZIP.
    import tempfile
    with tempfile.TemporaryDirectory() as temporary:
        layout = Path(temporary)
        for source in (report / 'ci').iterdir():
            shutil.copytree(source, layout / source.name)
        for target in BUILD_TARGETS:
            info = json.loads((layout / f'build-{target}/report.json').read_text())
            # Check the license copy the packager ships, as well as the
            # retained artifact license checked below by verify_evidence.
            if target == 'windows' and info.get('flutter_license_hash') != digest(root / '.tools/flutter/LICENSE'):
                raise ValueError('Flutter license differs from the prepared player.')
            for relative in info['generated_hashes']:
                safe_relative(relative)
                destination = layout / f'build-{target}/generated' / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / 'upstream' / relative, destination)
        for source, target in [(root / 'upstream/build/web', layout / 'build-web/web'),
                               (root / 'upstream/build/windows/x64/runner/Release', layout / 'build-windows/native'),
                               (linux / 'bundle', layout / 'build-linux/bundle')]:
            shutil.copytree(source, target)
        verify_evidence(root, layout)


def main() -> None:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['checks', 'build', 'verify', 'prepare'])
    parser.add_argument('--platform', choices=BUILD_TARGETS)
    parser.add_argument('--shard', type=int, default=0)
    parser.add_argument('--artifacts', type=Path, default=Path('.local/artifacts'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.mode == 'verify':
        verify_evidence(root, args.artifacts.resolve())
    elif args.mode == 'prepare':
        print(prepare_release(root, args.artifacts.resolve()))
    else:
        if args.platform is None:
            parser.error('--platform is required for workers')
        run_worker(root, args.mode, args.platform, args.shard)


if __name__ == '__main__':
    main()
