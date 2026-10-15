"""Package freshly checked Windows/web builds and their exact generated source."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from package_preview import (
    WEB_SCRIPTS, archive_package, cache_ignore, copy_file, digest, file_hashes,
    require_files, runtime_hashes, source_reference, write_json,
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


def package(root: Path, report: Path, runtime: Path, output: Path, tag: str, fingerprint: str, repository: str) -> dict:
    info = json.loads((report / 'build-info.json').read_text(encoding='utf-8-sig'))
    required = ['01-dependencies', '02-serialization', '03-tests', '04-focused-analysis',
                '05-full-analysis', '06-web-release', '07-offline-manifest', '08-windows-release']
    if (info['status'] != 'automated_checks_passed_manual_qa_pending'
            or [step['name'] for step in info['steps']] != required
            or any(step['exit_code'] != 0 for step in info['steps'])):
        raise ValueError('Both builds and all checks must pass before packaging a nightly.')
    if output.exists():
        raise ValueError(f'Choose a fresh nightly output directory: {output}')
    web = root / 'upstream/build/web'
    native = root / 'upstream/build/windows/x64/runner/Release'
    require_files(web, ('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'sw.js'))
    if 'const RESOURCES = null; // build: manifest' in (web / 'sw.js').read_text(encoding='utf-8'):
        raise ValueError('Web offline manifest was not injected.')
    require_files(native, ('lcs_new_age.exe', 'flutter_windows.dll', 'data/app.so',
                           'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z'))
    runtime_files = ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
    require_files(runtime, runtime_files)
    output.mkdir(parents=True)
    prefix = f'LCS-Underground-Edition-{tag}'
    source = output / f'{prefix}-Source'
    source.mkdir()
    # Tracked repository files preserve tooling, documentation and artwork provenance.
    tracked = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'],
                             check=True, capture_output=True).stdout.decode('utf-8').split('\0')
    for name in tracked:
        if name and not name.startswith('upstream/'):
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
    source_result = archive_package(source)
    source_archive = Path(source_result['archive']).name
    source_url = f'https://github.com/{repository}/releases/download/{tag}/{source_archive}'
    results = [source_result]
    for target, built, suffix in (('web', web, 'Web-Player'), ('windows-x64', native, 'Windows-x64-Player')):
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
            f'# The Underground Edition — Nightly\n\n{instructions}\n\n'
            'Automated development build. Export important saves before trying it. '
            'See SOURCE_REFERENCE.md for matching source, LICENSE and AUTHORS.md for credits, '
            'and licenses/ plus runtime NOTICES for component notices.\n', encoding='utf-8')
        (player / 'SOURCE_REFERENCE.md').write_text(
            source_reference(source_archive, source_result['archive_sha256'], source_url, identity), encoding='utf-8')
        write_json(player / 'BUILD_INFO.json', {**common, 'target': target, 'source_archive': source_archive,
                                               'source_archive_sha256': source_result['archive_sha256']})
        runtime_hashes(player, target)  # Fail on an incomplete runtime before sealing the archive.
        results.append(archive_package(player))
    # Neither packaging pass may mutate the corresponding game source.
    from package_preview import filtered_source_hashes
    if before != filtered_source_hashes(root / 'upstream'):
        raise ValueError('Game source changed while packaging.')
    assets = []
    for result in results:
        archive = Path(result['archive'])
        for path in (archive, archive.with_name(archive.name + '.sha256')):
            assets.append({'name': path.name, 'sha256': digest(path)})
    metadata = {'tag': tag, 'fingerprint': fingerprint, 'source_commit': info['source_commit'], 'assets': assets}
    write_json(output / 'nightly.json', metadata)
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    package(args.root.resolve(), args.report.resolve(), vc_runtime(), args.root.resolve() / 'release/nightly',
            os.environ['NIGHTLY_TAG'], os.environ['NIGHTLY_FINGERPRINT'], os.environ['GITHUB_REPOSITORY'])


if __name__ == '__main__':
    main()
