"""Build and check the Linux x64 bundle with the pinned SDK (run on Linux)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import shutil
import subprocess

from analysis_targets import focused_targets
from package_release import verify_source_checkout
from release_common import file_hashes, runtime_hashes, write_json


def build(root: Path, channel: str = 'Development') -> None:
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('Run this builder on Linux x64.')
    analysis = focused_targets(root)
    commit = (subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
              if (root / '.git').exists() else
              json.loads((root / 'BUILD_INFO.json').read_text())['source_commit'])
    verify_source_checkout(root, commit)
    pin = json.loads((root / 'scripts/toolchain.json').read_text())
    flutter = str(root / '.tools/flutter/bin/flutter')
    dart = str(root / '.tools/flutter/bin/dart')
    # Bootstrap output can precede --machine JSON on the first SDK invocation.
    try:
        subprocess.check_output([flutter, '--suppress-analytics', '--version'], text=True)
    except subprocess.CalledProcessError as error:
        raise ValueError(f'Flutter SDK bootstrap failed ({error.returncode}). {(error.output or "").strip()}') from error
    version = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    if (version['frameworkVersion'] != pin['flutter_version']
            or version['frameworkRevision'] != pin['flutter_revision']):
        raise ValueError('Flutter SDK does not match scripts/toolchain.json.')
    output = root / '.local/linux'
    output.mkdir(parents=True, exist_ok=False)
    report = output / 'evidence'
    report.mkdir()
    info = {'status': 'in_progress', 'source_commit': commit, 'toolchain': pin, 'steps': []}
    commands = [
        ('dependencies', [flutter, 'pub', 'get']),
        ('serialization', [dart, 'run', 'build_runner', 'build']),
        ('tests', [flutter, 'test', '--no-pub']),
        ('focused-analysis', [flutter, 'analyze', '--no-pub', *analysis]),
        ('full-analysis', [flutter, 'analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings']),
        ('linux-release', [flutter, 'build', 'linux', '--release', '--no-pub',
                           f'--dart-define=LCS_BUILD={commit[:8]}',
                           f'--dart-define=LCS_CHANNEL={channel}']),
    ]
    try:
        for name, command in commands:
            print(f'[{name}]', flush=True)
            with (report / f'{name}.log').open('w') as log:
                process = subprocess.Popen(command, cwd=root / 'upstream', stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True)
                for line in process.stdout:
                    print(line, end='', flush=True)
                    log.write(line)
                code = process.wait()
            info['steps'].append({'name': name, 'exit_code': code})
            if code:
                raise ValueError(f'{name} failed with exit {code}.')
        verify_source_checkout(root, commit)
        # Dereference any plugin library links before Actions transfers the files.
        shutil.copytree(root / 'upstream/build/linux/x64/release/bundle', output / 'bundle')
        runtime_hashes(output / 'bundle', 'linux-x64')
        info['bundle_hashes'] = file_hashes(output / 'bundle')
        info['status'] = 'passed'
    except Exception:
        info['status'] = 'failed'
        raise
    finally:
        write_json(report / 'build-info.json', info)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', choices=('Development', 'Preview', 'Nightly', 'Release'),
                        default='Development')
    arguments = parser.parse_args()
    build(Path(__file__).resolve().parent.parent, arguments.channel)
