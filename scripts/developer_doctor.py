"""Inspect local development prerequisites without installing, building or launching."""
from __future__ import annotations

import argparse
from importlib import metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parent.parent


def read_object(path: Path) -> dict:
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError(f'Expected a JSON object: {path}')
    return value


def toolchain(root: Path) -> dict:
    pin = read_object(root / 'scripts/toolchain.json')
    if (not isinstance(pin.get('flutter_version'), str) or not pin['flutter_version'] or
            not re.fullmatch(r'[0-9a-f]{40}', str(pin.get('flutter_revision', '')))):
        raise ValueError('scripts/toolchain.json has no valid Flutter version/revision.')
    return pin


def check_flutter(root: Path) -> str:
    """Read the bootstrapped cache; invoking Flutter can bootstrap/write the SDK."""
    pin = toolchain(root)
    sdk = root / '.tools/flutter'
    suffix = '.bat' if os.name == 'nt' else ''
    for relative in (f'bin/flutter{suffix}', f'bin/dart{suffix}',
                     f'bin/cache/dart-sdk/bin/dart{".exe" if os.name == "nt" else ""}',
                     'bin/cache/flutter_tools.snapshot'):
        if not (sdk / relative).is_file():
            raise ValueError(f'Pinned SDK is missing or has not been bootstrapped: {relative}')
    version = read_object(sdk / 'bin/cache/flutter.version.json')
    if (version.get('frameworkVersion') != pin['flutter_version'] or
            version.get('frameworkRevision') != pin['flutter_revision']):
        raise ValueError(f'SDK cache differs from the pin: expected {pin["flutter_version"]} '
                         f'at {pin["flutter_revision"]}.')
    # Without this guard Git could find the game's parent repository instead.
    if not (sdk / '.git').exists():
        raise ValueError('Pinned SDK Git metadata is missing; follow docs/BUILDING.md.')
    revision = subprocess.check_output(
        ['git', '--no-optional-locks', '-C', str(sdk), 'rev-parse', '--verify', 'HEAD'],
        text=True, stderr=subprocess.PIPE, timeout=15).strip()
    if revision != pin['flutter_revision']:
        raise ValueError(f'SDK checkout is {revision}; expected {pin["flutter_revision"]}. '
                         'Its cached version metadata may be stale.')
    return f'Flutter {pin["flutter_version"]} at {revision[:12]}; bootstrapped cache present.'


def local_uri(base: Path, value: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError('Package configuration contains an invalid local URI.')
    uri = urlparse(urljoin(base.as_uri(), value))
    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost') or uri.query or uri.fragment:
        raise ValueError(f'Package configuration contains a non-local URI: {value}')
    return Path(url2pathname(uri.path)).resolve()


def app_package_name(root: Path) -> str:
    # Read only this repository's top-level name scalar; pub remains the YAML
    # authority. Unsupported/ambiguous forms need review rather than a guess.
    manifest = (root / 'upstream/pubspec.yaml').read_text(encoding='utf-8-sig')
    declarations = re.findall(r'^name[ \t]*:(.*)$', manifest, re.MULTILINE)
    name = re.fullmatch(r'''[ \t]*(?P<quote>['"]?)(?P<name>[a-z_][a-z0-9_]*)(?P=quote)(?:[ \t]+#.*)?[ \t]*''',
                        declarations[0]) if len(declarations) == 1 else None
    if name is None:
        raise ValueError('Expected one simple package name in upstream/pubspec.yaml.')
    return name['name']


def check_dart_packages(root: Path) -> str:
    pin = toolchain(root)
    path = root / 'upstream/.dart_tool/package_config.json'
    config = read_object(path)
    packages = config.get('packages')
    if config.get('configVersion') != 2 or not isinstance(packages, list) or not packages:
        raise ValueError('Dart package configuration is invalid or empty.')
    if (config.get('flutterVersion') != pin['flutter_version'] or
            local_uri(path, config.get('flutterRoot')) != (root / '.tools/flutter').resolve()):
        raise ValueError('Dart dependencies were resolved with a different Flutter SDK or checkout.')
    app = app_package_name(root)
    missing, app_roots = [], []
    for package in packages:
        if not isinstance(package, dict) or not isinstance(package.get('name'), str):
            raise ValueError('Dart package configuration contains an invalid package.')
        package_root = local_uri(path, package.get('rootUri'))
        if package['name'] == app:
            app_roots.append(package_root)
        if not package_root.is_dir():
            missing.append(package['name'])
    if len(app_roots) != 1:
        raise ValueError(f'Package configuration must contain exactly one {app} app package.')
    if app_roots[0] != (root / 'upstream').resolve():
        raise ValueError(f'Dart app package {app} points to a different checkout.')
    if missing:
        raise ValueError(f'Dart package roots are missing: {", ".join(missing)}.')
    return f'{len(packages)} resolved package roots exist for this checkout and Flutter version.'


def check_generated_sources(root: Path) -> str:
    """Check source-authored, single-line generated-part references for presence."""
    root = root.resolve()
    library = root / 'upstream/lib'
    if not library.is_dir():
        raise ValueError('Dart source directory is missing: upstream/lib.')
    # The repository's serializer declarations use ordinary quoted part URIs
    # on their own line. This is a presence inventory, not a Dart parser/linter.
    directive = re.compile(r"""^[ \t]*part[ \t]+(['"])([^'"\r\n]+\.g\.dart)\1[ \t]*;[ \t]*(?://[^\r\n]*)?$""",
                           re.MULTILINE)
    outputs = set()
    for source in sorted(library.rglob('*.dart')):
        if source.name.endswith('.g.dart') or not source.is_file():
            continue
        for match in directive.finditer(source.read_text(encoding='utf-8-sig')):
            target = source.parent / match[2]
            if not target.resolve().is_relative_to(library):
                raise ValueError(f'Generated part escapes upstream/lib: {source.relative_to(root).as_posix()} -> {match[2]}')
            outputs.add(target)
    missing = [path.relative_to(root).as_posix() for path in sorted(outputs) if not path.is_file()]
    if missing:
        raise ValueError('Missing or non-file generated source outputs: ' + ', '.join(missing))
    return f'{len(outputs)} referenced .g.dart output{"s" if len(outputs) != 1 else ""} present; presence only, freshness not checked.'


def check_node() -> str:
    executable = shutil.which('node')
    if not executable:
        raise ValueError('Node.js is not on PATH.')
    version = subprocess.check_output([executable, '--version'], text=True,
                                      stderr=subprocess.PIPE, timeout=15).strip()
    if not re.fullmatch(r'v\d+\.\d+\.\d+', version):
        raise ValueError(f'Node.js returned an unrecognized version: {version}')
    return version


def check_node_packages(root: Path, package: str, node_version: str | None) -> str:
    directory = root / 'upstream/tool' / package
    manifest = read_object(directory / 'package.json')
    lock = read_object(directory / 'package-lock.json')
    packages = lock.get('packages')
    if lock.get('lockfileVersion') != 3 or not isinstance(packages, dict) or not isinstance(packages.get(''), dict):
        raise ValueError('Expected the committed npm v3 package lock.')
    for field in ('dependencies', 'devDependencies', 'engines'):
        declared = manifest.get(field, {})
        if not isinstance(declared, dict) or declared != packages[''].get(field, {}):
            raise ValueError(f'package.json {field} differs from package-lock.json.')
    count = 0
    for name, locked in packages.items():
        if not isinstance(locked, dict):
            raise ValueError(f'Invalid locked package: {name}')
        # Lock paths can include scoped and nested packages, but never escape
        # this project's node_modules tree. No installed JavaScript is run.
        if name and (not name.startswith('node_modules/') or '\\' in name or
                     any(part in ('.', '..', '') for part in name.split('/'))):
            raise ValueError(f'Invalid locked package path: {name}')
        installed_path = directory / name / 'package.json'
        if name and locked.get('optional') and not installed_path.is_file():
            continue
        engines = locked.get('engines', {})
        if not isinstance(engines, dict):
            raise ValueError(f'Invalid locked engines: {name or package}')
        if node_version:
            requirement = engines.get('node')
            if requirement:
                minimum = re.fullmatch(r'>=\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?', requirement)
                if not minimum:
                    raise ValueError(f'Node requirement needs manual review: {name or package}: {requirement}')
                expected = tuple(int(part or 0) for part in minimum.groups())
                actual = tuple(int(part) for part in node_version.lstrip('v').split('.'))
                if actual < expected:
                    raise ValueError(f'Node {node_version} does not meet {name or package}: {requirement}.')
        if not name:
            continue
        installed = read_object(installed_path)
        if not locked.get('version') or installed.get('version') != locked['version']:
            raise ValueError(f'{name} differs from its locked version {locked.get("version")}.')
        count += 1
    if not count:
        raise ValueError('npm package lock contains no installed dependencies.')
    return f'{count} installed package versions match {package}/package-lock.json.'


def check_pillow(root: Path) -> str:
    requirements = (root / 'scripts/requirements-art.txt').read_text(encoding='utf-8')
    pins = re.findall(r'^Pillow==([^\s#]+)\s*(?:#.*)?$', requirements, re.MULTILINE | re.IGNORECASE)
    if len(pins) != 1:
        raise ValueError('Expected one exact Pillow pin in scripts/requirements-art.txt.')
    try:
        installed = metadata.version('Pillow')
    except metadata.PackageNotFoundError as error:
        raise ValueError('Pillow is not installed for this Python interpreter.') from error
    if installed != pins[0]:
        raise ValueError(f'Pillow {installed} is installed; the tooling requires {pins[0]}.')
    return f'Pillow {installed} for {sys.executable}.'


def diagnose(root: Path, *, browser=False, mcp=False, tooling=False) -> dict:
    checks = []

    def collect(name, operation, remedy):
        try:
            detail = operation()
            checks.append({'name': name, 'status': 'passed', 'detail': detail})
            return detail
        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
            checks.append({'name': name, 'status': 'failed', 'detail': str(error), 'remedy': remedy})
            return None

    collect('flutter', lambda: check_flutter(root),
            'Install/initialize the pinned SDK using docs/BUILDING.md#toolchain, then follow Development mode.')
    collect('dart-packages', lambda: check_dart_packages(root),
            'Run the pinned Flutter pub get from upstream/; see docs/BUILDING.md#development-mode.')
    generator = '..\\.tools\\flutter\\bin\\dart.bat' if os.name == 'nt' else '../.tools/flutter/bin/dart'
    collect('generated-sources', lambda: check_generated_sources(root),
            f'From upstream/, run {generator} run build_runner build with the pinned SDK; see docs/BUILDING.md#development-mode.')
    if browser or mcp:
        node = collect('node', check_node, 'Install Node.js matching the engines in the committed npm lockfiles; reopen the shell.')
        collect('browser-packages', lambda: check_node_packages(root, 'offline_test', node),
                'Run npm ci --prefix upstream/tool/offline_test --no-audit --no-fund.')
    if mcp:
        collect('mcp-packages', lambda: check_node_packages(root, 'dev_mcp', node),
                'Run npm ci --prefix upstream/tool/dev_mcp --no-audit --no-fund.')
    if tooling:
        collect('python-art-packages', lambda: check_pillow(root),
                f'Run python -m pip install -r scripts/requirements-art.txt using {sys.executable}.')
    return {'schema': 1, 'root': str(root), 'python': sys.version.split()[0],
            'status': 'failed' if any(check['status'] == 'failed' for check in checks) else 'passed',
            'scope': 'Local prerequisite inventory including generated-output presence; code checks, serializer freshness, browser launch and build acceptance remain separate.',
            'checks': checks}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', action='store_true', help='Also inspect Node and browser-helper dependencies.')
    parser.add_argument('--mcp', action='store_true', help='Also inspect Node, browser-helper and development MCP dependencies.')
    parser.add_argument('--tooling', action='store_true', help='Also inspect the pinned Python image-tooling dependency.')
    parser.add_argument('--json', action='store_true', help='Print machine-readable diagnostics to stdout.')
    args = parser.parse_args(argv)
    result = diagnose(ROOT, browser=args.browser, mcp=args.mcp, tooling=args.tooling)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(result['scope'])
        for check in result['checks']:
            print(f'{check["status"].upper()} {check["name"]}: {check["detail"]}')
            if check.get('remedy'):
                print(f'  Next: {check["remedy"]}')
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
