"""Skip unchanged nightly inputs and publish a complete, separately tagged prerelease."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

from package_preview import digest

MARKER = '<!-- lcs-nightly-inputs:'
INPUTS = ('upstream', 'scripts', '.github', 'Play.cmd')


def git(*args: str) -> str:
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True).stdout.strip()


def fingerprint() -> str:
    # Blob/tree identities ignore commit messages and documentation-only commits.
    inventory = git('ls-tree', '-r', 'HEAD', '--', *INPUTS)
    return hashlib.sha256(inventory.encode('utf-8')).hexdigest()


def gh(*args: str) -> str:
    return subprocess.run(['gh', *args], check=True, capture_output=True, text=True).stdout


def managed(release: dict) -> bool:
    return (release.get('name') == 'Nightly' and release.get('prerelease') is True
            and re.fullmatch(r'nightly-\d+-\d+', release.get('tag_name', '')) is not None
            and MARKER in (release.get('body') or ''))


def releases(repository: str) -> list[dict]:
    pages = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repository}/releases?per_page=100'))
    return [release for page in pages for release in page]


def latest_successful(items: list[dict]) -> dict | None:
    published = [item for item in items if managed(item) and not item.get('draft')]
    return max(published, key=lambda item: item['published_at'], default=None)


def changed_since(latest: dict | None, value: str) -> bool:
    return latest is None or f'{MARKER}{value} -->' not in (latest.get('body') or '')


def check(repository: str) -> None:
    value = fingerprint()
    changed = changed_since(latest_successful(releases(repository)), value)
    tag = f"nightly-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
        output.write(f'changed={str(changed).lower()}\nfingerprint={value}\ntag={tag}\n')
    message = 'Build inputs changed; building Windows and web.' if changed else 'Build inputs unchanged since the last published nightly; skipped.'
    print(message)
    with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as summary:
        summary.write(message + '\n')


def publish(repository: str, output: Path) -> None:
    metadata = json.loads((output / 'nightly.json').read_text(encoding='utf-8'))
    tag = os.environ['NIGHTLY_TAG']
    value = os.environ['NIGHTLY_FINGERPRINT']
    commit = git('rev-parse', 'HEAD')
    if (metadata['tag'] != tag or metadata['fingerprint'] != value
            or metadata['source_commit'] != commit or fingerprint() != value
            or not re.fullmatch(r'nightly-\d+-\d+', tag)):
        raise ValueError('Nightly identity does not match this build.')
    assets = [output / item['name'] for item in metadata['assets']]
    if len(assets) != 6 or len(set(assets)) != 6:
        raise ValueError('Expected three archives and their checksum sidecars.')
    for path, item in zip(assets, metadata['assets']):
        if path.parent != output or not path.is_file() or digest(path) != item['sha256']:
            raise ValueError(f'Nightly asset missing or changed: {path}')
    notes = output / 'release-notes.md'
    notes.write_text(
        f'Automated Windows x64 and browser builds from `{commit}`.\n\n'
        'Download a player ZIP and extract the whole folder. Windows: run `lcs_new_age.exe`. '
        'Web: run `Play.cmd` (requires Python 3). The Source ZIP is the matching modified source; '
        'keep it alongside the player downloads when redistributing.\n\n'
        'Tests, analysis, both release builds and archive integrity checks passed. '
        'Automated nightlies have no manual gameplay or clean-machine launch certification. '
        'Export important saves before trying a nightly.\n\n'
        f'[Build logs](https://github.com/{repository}/actions/runs/{os.environ["GITHUB_RUN_ID"]})\n\n'
        f'{MARKER}{value} -->\n', encoding='utf-8',
    )
    previous = releases(repository)
    # Unique draft tags keep all old assets available until the new set is complete.
    gh('release', 'create', tag, '--repo', repository, '--target', commit,
       '--title', 'Nightly', '--notes-file', str(notes), '--draft', '--prerelease', '--latest=false')
    gh('release', 'upload', tag, *map(str, assets), '--repo', repository)
    uploaded = json.loads(gh('release', 'view', tag, '--repo', repository, '--json', 'assets'))['assets']
    expected = {path.name: path.stat().st_size for path in assets}
    if {item['name']: item['size'] for item in uploaded} != expected:
        raise ValueError('Uploaded nightly assets do not match the complete local set; draft retained.')
    gh('release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease', '--latest=false')
    # Verify publication before retiring any old nightly. Never select preview tags.
    current = json.loads(gh('api', f'repos/{repository}/releases/tags/{tag}'))
    if current['draft'] or not managed(current):
        raise ValueError('Nightly publication could not be verified; previous nightly retained.')
    for old in previous:
        if managed(old) and old['tag_name'] != tag:
            try:
                gh('release', 'delete', old['tag_name'], '--repo', repository, '--yes', '--cleanup-tag')
            except subprocess.CalledProcessError:
                print(f'::warning::Could not retire older nightly {old["tag_name"]}; new nightly is published.')
    url = current['html_url']
    print(f'Published {url}')
    with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as summary:
        summary.write(f'\n[Nightly downloads]({url})\n')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check', 'publish'))
    args = parser.parse_args()
    repository = os.environ['GITHUB_REPOSITORY']
    if args.action == 'check':
        check(repository)
    else:
        publish(repository, Path('release/nightly'))


if __name__ == '__main__':
    main()
