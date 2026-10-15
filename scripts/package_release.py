"""Package checked web/Windows players and one matching source archive."""
from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime, timezone
import shutil
import subprocess
from pathlib import Path

from release_common import (
    WEB_SCRIPTS, archive_package, cache_ignore, copy_file, digest, file_hashes,
    filtered_source_hashes, require_files, runtime_hashes, source_reference, write_json,
)


def vc_runtime() -> Path:
    vswhere = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    installation = subprocess.run(
        [str(vswhere), '-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
         '-property', 'installationPath'], check=True, capture_output=True, text=True,
    ).stdout.strip()
    if not installation:
        raise ValueError('Visual Studio C++ toolchain was not found.')
    candidates = sorted((Path(installation) / 'VC/Redist/MSVC').glob('*/x64/Microsoft.VC143.CRT'))
    if not candidates:
        raise ValueError('Visual C++ x64 redistributable DLLs were not found.')
    return candidates[-1]


def package(root: Path, report: Path, runtime: Path | None, output: Path, tag: str, fingerprint: str | None, repository: str) -> dict:
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', tag):
        raise ValueError('Invalid release tag.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid GitHub repository.')
    info = json.loads((report / 'build-info.json').read_text(encoding='utf-8-sig'))
    required = ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                '05-full-analysis', '06-web-release', '07-offline-manifest']
    if runtime is not None:
        required.append('08-windows-release')
    if (info['status'] != 'automated_checks_passed_manual_qa_pending'
            or [step['name'] for step in info['steps']] != required
            or any(step['exit_code'] != 0 for step in info['steps'])):
        raise ValueError('Both builds and all checks must pass before packaging a Windows release.' if runtime is not None else 'The web build and all checks must pass before packaging.')
    if output.exists():
        raise ValueError(f'Choose a fresh release output directory: {output}')
    web = root / 'upstream/build/web'
    native = root / 'upstream/build/windows/x64/runner/Release'
    require_files(web, ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'))
    if 'const RESOURCES = null; // build: manifest' in (web / 'sw.js').read_text(encoding='utf-8'):
        raise ValueError('Web offline manifest was not injected.')
    runtime_files = ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
    if runtime is not None:
        require_files(native, ('lcs_new_age.exe', 'flutter_windows.dll', 'data/app.so',
                              'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z'))
        require_files(runtime, runtime_files)
    output.mkdir(parents=True)
    prefix = f'LCS-Underground-Edition-{tag}'
    source = output / f'{prefix}-Source'
    source.mkdir()
    # Tracked repository files preserve tooling, documentation and artwork provenance.
    if (root / '.git').exists():
        tracked = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'],
                                 check=True, capture_output=True).stdout.decode('utf-8').split('\0')
        for name in tracked:
            if name and not name.startswith('upstream/') and Path(name).parts[0] not in {'.tools', '.local', 'reports', 'release'}:
                copy_file(root / name, source / name)
    else:
        # A prepared source archive is also a supported rebuild root.
        for name in ('scripts', 'docs', 'assets', '.github'):
            if (root / name).is_dir():
                shutil.copytree(root / name, source / name, ignore=cache_ignore)
        for name in ('README.md', 'AUTHORS.md', 'LICENSE', 'Play.cmd', '.gitignore'):
            copy_file(root / name, source / name)
    # Include build_runner outputs and platform source; omit SDKs and build caches.
    shutil.copytree(root / 'upstream', source / 'upstream', ignore=cache_ignore)
    before = file_hashes(source / 'upstream')
    if not any(name.endswith('.g.dart') for name in before):
        raise ValueError('Generated serialization source is missing.')
    shutil.copytree(report, source / 'build-evidence', ignore=shutil.ignore_patterns('*package*.log'))
    identity = {'runtime_source_commit': info['source_commit'], 'packaging_commit': info['source_commit']}
    common = {**identity, 'source_commit': info['source_commit'], 'release_tag': tag,
              'fingerprint': fingerprint, 'verification_scope': 'Automated checks only; manual gameplay and clean-machine launch QA pending.'}
    write_json(source / 'BUILD_INFO.json', {**common, 'target': 'corresponding-source', 'toolchain': info['toolchain']})
    (source / 'SOURCE_INFO.md').write_text(
        '# Corresponding source\n\n'
        'The modified game is under `upstream/`, including generated serializers, locked dependencies '
        'and runtime artwork. Build from this folder using `docs/BUILDING.md`; no Git history is needed. '
        'Tests and automated build logs are under `build-evidence/`. Those checks do not certify '
        'every gameplay path or a clean-machine native launch.\n\n'
        f"Source revision: `{info['source_commit']}`. See LICENSE and AUTHORS.md.\n", encoding='utf-8')
    source_result = archive_package(source)
    source_archive = Path(source_result['archive']).name
    source_url = (f'https://github.com/{repository}/releases/download/{tag}/{source_archive}'
                  if fingerprint is not None else f'../{source_archive}')
    results = [source_result]
    targets = [('web', web, 'Web-Player')]
    if runtime is not None:
        targets.append(('windows-x64', native, 'Windows-x64-Player'))
    for target, built, suffix in targets:
        player = output / f'{prefix}-{suffix}'
        if target == 'web':
            shutil.copytree(built, player / 'web', ignore=shutil.ignore_patterns('*.map', '*.symbols', '.last_build_id'))
            copy_file(root / 'Play.cmd', player / 'Play.cmd')
            for name in WEB_SCRIPTS:
                copy_file(root / 'scripts' / name, player / 'scripts' / name)
            instructions = ('Extract the entire folder, then run Play.cmd. Python 3 is required. '
                            'Keep the same browser and http://127.0.0.1:8765/ address to retain saves. '
                            'On other systems: python3 scripts/serve.py --directory web --port 8765')
        else:
            shutil.copytree(built, player, ignore=shutil.ignore_patterns('*.pdb', '*.exp', '*.lib'))
            for name in runtime_files:
                copy_file(runtime / name, player / name)
            instructions = ('Extract the entire folder, then run lcs_new_age.exe. Keep data/ and all DLLs '
                            'beside it. Windows 10/11 x64; Python and Flutter are not required.')
        for name in ('LICENSE', 'AUTHORS.md'):
            copy_file(root / name, player / name)
        for original, name in ((root / '.tools/flutter/LICENSE', 'Flutter-LICENSE.txt'),
                               (root / 'upstream/fonts/journal/OFL.txt', 'LibreBaskerville-OFL.txt'),
                               (root / 'upstream/fonts/modern/roboto_license.txt', 'Roboto-LICENSE.txt')):
            copy_file(original, player / 'licenses' / name)
        (player / 'README.md').write_text(
            f'# The Underground Edition\n\nBuild: `{tag}`.\n\n{instructions}\n\n'
            'Export important saves before trying a development build. '
            'See SOURCE_REFERENCE.md for matching source, LICENSE and AUTHORS.md for credits, '
            'and licenses/ plus runtime NOTICES for component notices.\n', encoding='utf-8')
        (player / 'SOURCE_REFERENCE.md').write_text(
            source_reference(source_archive, source_result['archive_sha256'], source_url, identity), encoding='utf-8')
        write_json(player / 'BUILD_INFO.json', {**common, 'target': target, 'source_archive': source_archive,
                                               'source_archive_sha256': source_result['archive_sha256']})
        runtime_hashes(player, target)  # Fail on an incomplete runtime before sealing the archive.
        results.append(archive_package(player))
    # Neither packaging pass may mutate the corresponding game source.
    if before != filtered_source_hashes(root / 'upstream'):
        raise ValueError('Game source changed while packaging.')
    assets = []
    for result in results:
        archive = Path(result['archive'])
        for path in (archive, archive.with_name(archive.name + '.sha256')):
            assets.append({'name': path.name, 'sha256': digest(path)})
    metadata = {'tag': tag, 'fingerprint': fingerprint, 'source_commit': info['source_commit'], 'assets': assets}
    write_json(output / 'release.json', metadata)
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--windows', action='store_true')
    parser.add_argument('--nightly', action='store_true')
    parser.add_argument('--tag')
    parser.add_argument('--repository', default='woodk123/lcs-underground-edition')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root, report = args.root.resolve(), args.report.resolve()
    info = json.loads((report / 'build-info.json').read_text(encoding='utf-8-sig'))
    tag = os.environ['NIGHTLY_TAG'] if args.nightly else args.tag or f"local-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}-{info['source_commit'][:8]}"
    fingerprint = os.environ['NIGHTLY_FINGERPRINT'] if args.nightly else None
    repository = os.environ['GITHUB_REPOSITORY'] if args.nightly else args.repository
    output = args.output.resolve() if args.output else root / 'release' / ('nightly' if args.nightly else tag)
    result = package(root, report, vc_runtime() if args.windows or args.nightly else None,
                     output, tag, fingerprint, repository)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
