"""Prepare a traceable, cached development-only web player for the game MCP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import tomllib

from developer_doctor import check_node, check_node_packages
from release_common import digest, file_hashes, write_json

ROOT = Path(__file__).resolve().parent.parent
INPUTS = ('upstream/lib', 'upstream/assets', 'upstream/fonts', 'upstream/web',
          'upstream/pubspec.yaml', 'upstream/pubspec.lock',
          'upstream/tool/inject_service_worker.dart', 'scripts/toolchain.json',
          'scripts/prepare_dev_mcp.py', 'scripts/release_common.py')


def source_identity(root: Path) -> dict:
    commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z',
                                    '--cached', '--others', '--exclude-standard', '--', *INPUTS])
    inputs = set(names.decode('utf-8').split('\0')) - {''}
    # build_runner outputs are ignored by Git but are real compiler inputs.
    # Include their bytes so editing/deleting one cannot reuse an older player.
    inputs.update(path.relative_to(root).as_posix()
                  for path in (root / 'upstream/lib').rglob('*.g.dart') if path.is_file())
    checksum = hashlib.sha256()
    for name in sorted(inputs):
        path = root / name
        checksum.update(f'{name}\0{digest(path) if path.is_file() else "missing"}\0'.encode('utf-8'))
    return {'commit': commit, 'inputs_sha256': checksum.hexdigest()}


def valid_source(source: object) -> bool:
    return isinstance(source, dict) and all(
        isinstance(source.get(key), str) and re.fullmatch(pattern, source[key])
        for key, pattern in (('commit', r'[0-9a-f]{40}'), ('inputs_sha256', r'[0-9a-f]{64}')))


def cached_build(path: Path, source: dict, web: Path) -> dict | None:
    try:
        info = json.loads(path.read_text(encoding='utf-8'))
        if (not isinstance(info, dict) or info.get('schema') != 1 or info.get('status') != 'ready'
                or not valid_source(source) or not valid_source(info.get('source'))
                or info['source']['inputs_sha256'] != source['inputs_sha256']
                or info.get('build_id') != f'{info["source"]["commit"][:8]}-{info["source"]["inputs_sha256"][:8]}'
                or info.get('web_root') != str(web)
                or info.get('devtools') is not True):
            return None
        if not all((web / name).is_file() for name in ('main.dart.js', 'index.html', 'sw.js')):
            return None
        if info.get('payload_hashes') != file_hashes(web):
            return None
        if info.get('main_js_sha256') != digest(web / 'main.dart.js'):
            return None
        return info
    except (OSError, ValueError, TypeError):
        return None


def output_directory(root: Path, value: str) -> Path:
    output = (root / value).resolve()
    if not any(output.is_relative_to(root / parent) and output != root / parent
               for parent in ('.local', 'reports')):
        raise ValueError('Development builds must be inside .local/ or reports/.')
    output.mkdir(parents=True, exist_ok=True)
    return output


def run(command: list[str], cwd: Path) -> None:
    label = json.dumps(command)
    print(f'RUN {label}\nCWD {json.dumps(str(cwd))}', flush=True)
    started = time.perf_counter()
    try:
        subprocess.run(command, cwd=cwd, check=True)
    except BaseException:
        print(f'FAIL after {time.perf_counter() - started:.2f}s: {label}', flush=True)
        raise
    print(f'PASS after {time.perf_counter() - started:.2f}s: {label}', flush=True)


def install_dependencies(root: Path, output: Path) -> None:
    npm = shutil.which('npm.cmd' if os.name == 'nt' else 'npm')
    if not npm:
        raise ValueError('Install Node.js 20 or later and npm; see docs/DEV_MCP.md.')
    node_version = check_node()
    marker = output / 'dependencies.json'
    try:
        previous = json.loads(marker.read_text())
    except (OSError, ValueError):
        previous = {}
    if not isinstance(previous, dict):
        previous = {}
    current = {}
    for package in ('offline_test', 'dev_mcp'):
        directory = root / 'upstream/tool' / package
        current[package] = digest(directory / 'package-lock.json')
        try:
            check_node_packages(root, package, None)
        except (OSError, ValueError, TypeError, KeyError):
            needs_install = True
        else:
            # A runtime requirement failure cannot be repaired by reinstalling
            # healthy packages, including when the marker's lock hash is stale.
            check_node_packages(root, package, node_version)
            needs_install = previous.get(package) != current[package]
        if needs_install:
            run([npm, 'ci', '--prefix', str(directory), '--include=dev', '--no-audit', '--no-fund'], root)
            check_node_packages(root, package, node_version)
    write_json(marker, current)


def configure_codex(root: Path) -> Path:
    """Append only this project's server; retain all existing settings verbatim."""
    node = shutil.which('node')
    if not node:
        raise ValueError('Node.js is required.')
    path = root / '.codex/config.toml'
    text = path.read_text(encoding='utf-8') if path.exists() else ''
    existing = tomllib.loads(text).get('mcp_servers', {}).get('lcs_development')
    settings = {'command': Path(node).as_posix(),
                'args': [(root / 'scripts/dev_mcp/server.mjs').as_posix()],
                'cwd': root.as_posix(), 'startup_timeout_sec': 15, 'tool_timeout_sec': 60}
    if existing is not None:
        if any(existing.get(key) != value for key, value in settings.items()):
            raise ValueError(f'{path} already configures lcs_development differently; review it manually.')
        return path
    block = '\n[mcp_servers.lcs_development]\n' + ''.join(
        f'{key} = {json.dumps(value)}\n' for key, value in settings.items())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + ('\n' if text and not text.endswith('\n') else '') + block, encoding='utf-8')
    return path


def prepare(args) -> dict:
    output = output_directory(ROOT, args.out)
    suffix = '.bat' if os.name == 'nt' else ''
    flutter = ROOT / f'.tools/flutter/bin/flutter{suffix}'
    dart = ROOT / f'.tools/flutter/bin/dart{suffix}'
    if not flutter.is_file() or not dart.is_file():
        raise ValueError('Install the pinned Flutter SDK; see docs/BUILDING.md.')
    pin = json.loads((ROOT / 'scripts/toolchain.json').read_text())
    # The first SDK invocation can write bootstrap progress to machine stdout.
    # Warm it without resolving this project's packages or changing source.
    try:
        subprocess.check_output([str(flutter), '--suppress-analytics', '--version'], text=True)
    except subprocess.CalledProcessError as error:
        raise ValueError(f'Flutter SDK bootstrap failed ({error.returncode}). {(error.output or "").strip()}') from error
    sdk = json.loads(subprocess.check_output([str(flutter), '--version', '--machine'], text=True))
    if sdk['frameworkVersion'] != pin['flutter_version'] or sdk['frameworkRevision'] != pin['flutter_revision']:
        raise ValueError('Flutter SDK does not match scripts/toolchain.json.')
    install_dependencies(ROOT, output)
    source = source_identity(ROOT)
    web = output / 'web'
    manifest = output / 'build.json'
    info = None if args.rebuild else cached_build(manifest, source, web)
    if info:
        print(f'Reusing verified development build {info["build_id"]}; inputs match checkout {source["commit"][:8]}.', flush=True)
        return {**info, 'checked_source': source}
    write_json(manifest, {'schema': 1, 'status': 'building', 'source': source})
    run([str(flutter), 'pub', 'get'], ROOT / 'upstream')
    run([str(dart), 'run', 'build_runner', 'build'], ROOT / 'upstream')
    # Generated serializers are compilation inputs too.
    source = source_identity(ROOT)
    build_id = f'{source["commit"][:8]}-{source["inputs_sha256"][:8]}'
    run([str(flutter), 'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run',
         '--base-href', '/', f'--output={web}', '--dart-define=LCS_DEVTOOLS=true',
         f'--dart-define=LCS_BUILD={build_id}', '--dart-define=LCS_CHANNEL=Development'], ROOT / 'upstream')
    run([str(dart), 'run', 'tool/inject_service_worker.dart', str(web)], ROOT / 'upstream')
    if source_identity(ROOT) != source:
        raise ValueError('Game source changed during compilation; rerun after edits settle.')
    info = {'schema': 1, 'status': 'ready', 'devtools': True, 'source': source,
            'build_id': build_id, 'toolchain': pin, 'web_root': str(web),
            'main_js_sha256': digest(web / 'main.dart.js'), 'payload_hashes': file_hashes(web)}
    write_json(manifest, info)
    return {**info, 'checked_source': source}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', default='.local/dev-mcp')
    parser.add_argument('--rebuild', action='store_true', help='Rebuild even when input and payload hashes match.')
    parser.add_argument('--configure-codex', action='store_true', help='Add this MCP to the local project Codex config.')
    parser.add_argument('--check', action='store_true', help='Read-only input/payload check; print compiled and checked source identities without building.')
    args = parser.parse_args()
    try:
        if args.check:
            output = (ROOT / args.out).resolve()
            source = source_identity(ROOT)
            info = cached_build(output / 'build.json', source, output / 'web')
            if not info:
                raise ValueError('Development MCP build is missing, stale or modified; run python scripts/prepare_dev_mcp.py.')
            print(json.dumps({**{key: info[key] for key in ('web_root', 'build_id', 'main_js_sha256', 'source')},
                              'checked_source': source}))
            return
        info = prepare(args)
        if args.configure_codex:
            print(f'Configured {configure_codex(ROOT)}; reconnect MCP servers or start a new chat to load it.')
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps({key: info[key] for key in ('web_root', 'build_id', 'main_js_sha256', 'source', 'checked_source')}, indent=2))
    print('Ready. Start the MCP server with: node scripts/dev_mcp/server.mjs')


if __name__ == '__main__':
    main()
