"""Download the latest published, managed nightly for the Pages deployment."""
from __future__ import annotations

import argparse
import os
from pathlib import Path

from nightly_release import gh, latest_successful, releases


def download(repository: str, output: Path) -> str:
    latest = latest_successful(releases(repository))
    if latest is None:
        raise ValueError('No successfully published managed Nightly is available.')
    tag = latest['tag_name']
    prefix = f'LCS-Underground-Edition-{tag}'
    names = [f'{prefix}-{target}.zip{suffix}'
             for target in ('Web-Player', 'Source') for suffix in ('', '.sha256')]
    available = {asset['name'] for asset in latest['assets']}
    if not set(names).issubset(available):
        raise ValueError('The published Nightly is missing web/source assets or checksums.')
    output.mkdir(parents=True, exist_ok=False)
    arguments = ['release', 'download', tag, '--repo', repository, '--dir', str(output)]
    for name in names:
        arguments.extend(['--pattern', name])
    gh(*arguments)
    print(f'Downloaded published Nightly {tag}')
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as stream:
            stream.write(f'tag={tag}\n')
    return tag


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.repository:
        parser.error('--repository or GITHUB_REPOSITORY is required')
    download(args.repository, args.output)
