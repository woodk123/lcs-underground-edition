"""Install/verify the pinned SDK and warm dependencies for cached CI workers."""
from pathlib import Path
import argparse
import json
import platform
import subprocess


TARGETS = ('tests', 'windows', 'linux', 'web')


def setup(root: Path, target: str) -> None:
    windows = platform.system() == 'Windows'
    if target not in TARGETS or (target in ('windows', 'linux') and
                                 target != ('windows' if windows else 'linux')):
        raise ValueError('SDK target does not match this host.')
    pin = json.loads((root / 'scripts/toolchain.json').read_text())
    sdk = root / '.tools/flutter'
    if not sdk.exists():
        subprocess.run(['git', '-c', 'core.longpaths=true', 'clone', '--depth', '1',
                        '--branch', pin['flutter_version'], pin['flutter_repository'], str(sdk)], check=True)
    flutter = str(sdk / ('bin/flutter.bat' if windows else 'bin/flutter'))
    # First invocation bootstraps Dart/the Flutter tool and prints progress to
    # stdout even with --machine. Warm it before reading structured version JSON.
    configuration = ['--enable-web' if target == 'web' else f'--enable-{target}-desktop'] if target != 'tests' else []
    subprocess.run([flutter, 'config', '--no-analytics', *configuration], check=True)
    version = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    if (version['frameworkRevision'] != pin['flutter_revision'] or
            version['frameworkVersion'] != pin['flutter_version']):
        raise ValueError('Cached SDK does not match the pinned toolchain.')
    # Explicit --universal avoids precache's default of downloading every
    # enabled platform. It includes flutter_tester, patched SDKs and fonts.
    artifacts = [] if target == 'tests' else [f'--{target}']
    subprocess.run([flutter, 'precache', '--universal', *artifacts], check=True)
    subprocess.run([flutter, 'pub', 'get'], cwd=root / 'upstream', check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=TARGETS, required=True)
    args = parser.parse_args()
    setup(Path(__file__).resolve().parent.parent, args.target)


if __name__ == '__main__':
    main()
