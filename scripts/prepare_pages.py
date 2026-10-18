"""Prepare GitHub Pages from verified release archives, without rebuilding the game."""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
import re
import shutil
import stat
import tempfile
import zipfile
import zlib

from release_common import HASH_RE, digest, require_files, safe_relative, verify_package


RESOURCES = re.compile(r'^const RESOURCES = (\{[^\r\n]*\});$', re.MULTILINE)
VERSION = re.compile(r"^const VERSION = '([0-9a-f]+)';$", re.MULTILINE)


def crc(data: bytes) -> str:
    return format(zlib.crc32(data), 'x')


def manifest_json(resources: dict) -> str:
    return json.dumps(resources, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def checked_extract(archive: Path, temporary: Path) -> Path:
    """Check the sidecar and every path before allowing any ZIP extraction."""
    sidecar = archive.with_name(archive.name + '.sha256')
    line = sidecar.read_text(encoding='utf-8-sig').strip()
    if (len(line) < 67 or not HASH_RE.fullmatch(line[:64])
            or line[64:66] != '  ' or line[66:] != archive.name
            or digest(archive) != line[:64]):
        raise ValueError(f'Archive SHA-256 does not match its sidecar: {archive}')
    folder = archive.stem
    with zipfile.ZipFile(archive) as bundle:
        names = set()
        for member in bundle.infolist():
            name = safe_relative(member.filename)
            if (not name.startswith(folder + '/') or name.casefold() in names
                    or stat.S_ISLNK(member.external_attr >> 16) or member.is_dir()):
                raise ValueError(f'Unsafe or duplicate ZIP entry: {name}')
            names.add(name.casefold())
        # archive_package emits regular files only; do not accept alternate ZIP layouts.
        bundle.extractall(temporary)
    shutil.copy2(archive, temporary / archive.name)
    shutil.copy2(sidecar, temporary / sidecar.name)
    package = temporary / folder
    verify_package(package)
    return package


def read_manifest(web: Path) -> tuple[str, dict]:
    worker = (web / 'sw.js').read_text(encoding='utf-8')
    manifests, versions = list(RESOURCES.finditer(worker)), list(VERSION.finditer(worker))
    if len(manifests) != 1 or len(versions) != 1:
        raise ValueError('Expected an injected service worker manifest and version.')
    resources = json.loads(manifests[0][1])
    if not resources or 'index.html' not in resources or 'main.dart.js' not in resources:
        raise ValueError('Service worker manifest is incomplete.')
    for name, checksum in resources.items():
        safe_relative(name)
        if name in {'sw.js', 'flutter_service_worker.js'} or crc((web / name).read_bytes()) != checksum:
            raise ValueError(f'Service worker resource hash mismatch: {name}')
    if crc(manifest_json(resources).encode('utf-8')) != versions[0][1]:
        raise ValueError('Service worker version does not match its manifest.')
    return worker, resources


def prepare(downloads: Path, output: Path, base_path: str, tag: str | None = None) -> dict:
    if not re.fullmatch(r'/(?:[A-Za-z0-9._-]+/)*', base_path) or any(
            part in {'.', '..'} for part in base_path.split('/')):
        raise ValueError('Base path must be / or a slash-delimited repository path.')
    downloads, output = downloads.resolve(strict=True), output.resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Output must be absent or an empty directory.')
    if tag is None:
        candidates = list(downloads.glob('LCS-Underground-Edition-nightly-*-*-Web-Player.zip'))
        if len(candidates) != 1:
            raise ValueError('Specify --tag or download exactly one nightly Web-Player ZIP.')
        tag = candidates[0].name.removeprefix('LCS-Underground-Edition-').removesuffix('-Web-Player.zip')
    nightly = bool(re.fullmatch(r'nightly-\d+-\d+', tag))
    if not nightly and not re.fullmatch(r'underground-v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected a managed nightly-N-N or numbered underground-vX.Y.Z tag.')
    prefix = f'LCS-Underground-Edition-{tag}'
    web_zip = downloads / f'{prefix}-Web-Player.zip'
    source_zip = downloads / f'{prefix}-Source.zip'
    with tempfile.TemporaryDirectory(prefix='lcs-pages-') as work:
        temporary = Path(work)
        player = checked_extract(web_zip, temporary)
        source = checked_extract(source_zip, temporary)
        require_files(player, ('LICENSE', 'AUTHORS.md', 'SOURCE_REFERENCE.md', 'BUILD_INFO.json',
                               'web/index.html', 'web/main.dart.js', 'web/flutter_bootstrap.js', 'web/sw.js'))
        if not (player / 'licenses').is_dir():
            raise ValueError('Player component licenses are missing.')
        info = json.loads((player / 'BUILD_INFO.json').read_text(encoding='utf-8'))
        source_info = json.loads((source / 'BUILD_INFO.json').read_text(encoding='utf-8'))
        if (info.get('release_tag') != tag or info.get('target') != 'web'
                or info.get('source_archive') != source_zip.name
                or info.get('source_archive_sha256') != digest(source_zip)
                or source_info.get('release_tag') != tag
                or source_info.get('target') != 'corresponding-source'
                or any(not info.get(key) or info[key] != source_info.get(key)
                        for key in ('runtime_source_commit', 'packaging_commit', 'source_commit'))
                or info.get('fingerprint') != source_info.get('fingerprint')
                or (nightly and not info.get('fingerprint'))):
            raise ValueError('Web and corresponding-source build metadata do not match.')
        worker, resources = read_manifest(player / 'web')
        staged = temporary / 'site'
        shutil.copytree(player / 'web', staged)
        for name in ('LICENSE', 'AUTHORS.md', 'SOURCE_REFERENCE.md', 'BUILD_INFO.json'):
            shutil.copy2(player / name, staged / name)
        shutil.copytree(player / 'licenses', staged / 'licenses')
        shutil.copy2(source_zip, staged / source_zip.name)
        shutil.copy2(source_zip.with_name(source_zip.name + '.sha256'), staged / (source_zip.name + '.sha256'))
        source_page = (
            '<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<title>Source and credits — The Underground Edition</title>'
            '<main><h1>The Underground Edition: source and credits</h1>'
            f'<p>{"Nightly" if nightly else "Release"} build: <code>{html.escape(tag)}</code>.</p>'
            f'<p><a href="{source_zip.name}">Download the complete matching source ZIP</a> '
            '(including build instructions, modified game source and artwork).</p>'
            f'<p>SHA-256: <code>{info["source_archive_sha256"]}</code></p>'
            '<p><a href="LICENSE">GPL v2 license</a> · <a href="AUTHORS.md">Authors and credits</a> · '
            '<a href="SOURCE_REFERENCE.md">Source provenance</a> · '
            '<a href="BUILD_INFO.json">Build metadata</a></p>'
            '<p>Component licenses: <a href="licenses/Flutter-LICENSE.txt">Flutter</a> · '
            '<a href="licenses/LibreBaskerville-OFL.txt">Libre Baskerville</a> · '
            '<a href="licenses/Roboto-LICENSE.txt">Roboto</a>. '
            'Additional runtime notices are included in the source ZIP.</p>'
            '<p><a href="./">Play the game</a></p></main></html>\n'
        )
        (staged / 'source.html').write_text(source_page, encoding='utf-8')
        index = (staged / 'index.html').read_text(encoding='utf-8')
        if index.count('<base href="/">') != 1 or index.count('<div class="bar"></div>') != 1:
            raise ValueError('Expected root base href and the managed loading screen in index.html.')
        index = index.replace('<base href="/">', f'<base href="{base_path}">', 1)
        index = index.replace('<div class="bar"></div>', '<div class="bar"></div>'
                              '<p><a href="source.html" style="color:inherit">Source and credits</a></p>', 1)
        (staged / 'index.html').write_text(index, encoding='utf-8')
        resources['index.html'] = crc((staged / 'index.html').read_bytes())
        manifest = manifest_json(resources)
        worker = RESOURCES.sub(lambda match: f'const RESOURCES = {manifest};', worker)
        version = crc(manifest.encode('utf-8'))
        worker = VERSION.sub(f"const VERSION = '{version}';", worker)
        (staged / 'sw.js').write_text(worker, encoding='utf-8')
        (staged / '.nojekyll').touch()
        read_manifest(staged)
        if digest(staged / 'main.dart.js') != digest(player / 'web/main.dart.js'):
            raise ValueError('Compiled game changed during Pages preparation.')
        shutil.copytree(staged, output, dirs_exist_ok=True)
    return {'tag': tag, 'base_path': base_path, 'source_archive': source_zip.name,
            'source_archive_sha256': info['source_archive_sha256'], 'service_worker_version': version}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--downloads', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--base-path', required=True)
    parser.add_argument('--tag', help='Managed nightly or numbered release tag; nightly inferred when unambiguous.')
    args = parser.parse_args()
    print(json.dumps(prepare(args.downloads, args.output, args.base_path, args.tag), indent=2))


if __name__ == '__main__':
    main()
