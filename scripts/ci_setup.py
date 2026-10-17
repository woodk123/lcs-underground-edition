"""Install/verify the pinned SDK and warm dependencies for cached CI workers."""
from pathlib import Path
import json
import platform
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    pin = json.loads((root / 'scripts/toolchain.json').read_text())
    sdk = root / '.tools/flutter'
    if not sdk.exists():
        subprocess.run(['git', '-c', 'core.longpaths=true', 'clone', '--depth', '1',
                        '--branch', pin['flutter_version'], pin['flutter_repository'], str(sdk)], check=True)
    windows = platform.system() == 'Windows'
    flutter = str(sdk / ('bin/flutter.bat' if windows else 'bin/flutter'))
    # First invocation bootstraps Dart/the Flutter tool and prints progress to
    # stdout even with --machine. Warm it before reading structured version JSON.
    subprocess.run([flutter, 'config', '--no-analytics',
                    '--enable-windows-desktop' if windows else '--enable-linux-desktop'], check=True)
    version = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    if (version['frameworkRevision'] != pin['flutter_revision'] or
            version['frameworkVersion'] != pin['flutter_version']):
        raise ValueError('Cached SDK does not match the pinned toolchain.')
    subprocess.run([flutter, 'precache', '--web', '--windows' if windows else '--linux'], check=True)
    subprocess.run([flutter, 'pub', 'get'], cwd=root / 'upstream', check=True)


if __name__ == '__main__':
    main()
