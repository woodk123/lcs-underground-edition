"""Check selected artwork provenance and portrait manifests without image libraries."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from release_common import digest, safe_relative


def verify(root: Path) -> dict:
    root = root.resolve()
    checked = set()

    def file(base: Path, name: str, expected: str | None = None) -> Path:
        path = (base / safe_relative(name)).resolve()
        if not path.is_relative_to(base.resolve()) or not path.is_file():
            raise ValueError(f'Missing or out-of-tree asset reference: {name}')
        if expected is not None and digest(path) != expected:
            raise ValueError(f'Asset hash mismatch: {path.relative_to(root)}')
        checked.add(path)
        return path

    def read(name: str) -> dict:
        return json.loads(file(root, name).read_text(encoding='utf-8-sig'))

    flags = ET.parse(file(root, 'upstream/assets/xml/flags.xml'))
    flag_assets = set()
    flag_directory = root / 'upstream/assets/flags'
    for flag in flags.findall('flagtype'):
        name = flag.findtext('asset', '').strip()
        if not name or Path(name).name != name or Path(name).suffix != '.svg':
            raise ValueError(f'Invalid flag asset: {name!r}')
        flag_assets.add(file(flag_directory, name))
    actual_flags = {path.resolve() for path in flag_directory.glob('*.svg')}
    if actual_flags != flag_assets:
        raise ValueError(f'Unreferenced flag assets: {sorted(str(path.relative_to(root)) for path in actual_flags - flag_assets)}')

    for name in ('assets/art-city-v2/atlas_metadata.json',
                 'assets/gangsters-journal/atlas_metadata.json'):
        metadata = read(name)
        for asset in metadata['assets'].values():
            file(root, asset['runtime_path'], asset.get('runtime_sha256', asset['sha256']))
            file(root, asset['original_path'], asset['sha256'])
            for key in ('prompt_path', 'initial_prompt_path'):
                if key in asset:
                    file(root, asset[key])
        for font in metadata.get('fonts', {}).values():
            file(root, font['runtime_path'], font['sha256'])

    runtime_art = read('assets/runtime-art/manifest.json')
    runtime_paths = set()
    for asset in runtime_art['assets']:
        file(root, asset['original_path'], asset['original_sha256'])
        file(root, asset['runtime_path'], asset['runtime_sha256'])
        runtime_paths.add(asset['runtime_path'])
    if len(runtime_paths) != len(runtime_art['assets']):
        raise ValueError('Duplicated runtime artwork references')

    # Coverage is tied to the authored catalogues, not just whichever subset a
    # renderer happens to support. New tangible types must bring their artwork.
    coverage = read('assets/catalogue/coverage.json')
    required = set()
    authored = set()
    for catalogue in ('weapons', 'clothing', 'ammo', 'loot', 'vehicles'):
        authored.update(node.attrib['idname'] for node in ET.parse(
            root / f'upstream/assets/xml/{catalogue}.xml').getroot()
            if 'idname' in node.attrib)
    entries = coverage['catalogues']
    declared = [entry['type_id'] for entry in entries]
    if len(declared) != len(set(declared)) or set(declared) != authored:
        raise ValueError('Coverage inventory differs from authored catalogues')
    exclusions = {'WEAPON_NONE', 'CLOTHING_NONE', 'WEAPON_BITE',
                  'WEAPON_PROBOSCIS', 'WEAPON_FIRE_BREATH'}
    excluded = {entry['type_id'] for entry in entries if not entry['illustration_required']}
    if excluded != exclusions:
        raise ValueError('Unexpected unillustrated catalogue types')
    required = authored - excluded
    paintings = set()
    runtime_records = {a['runtime_path']: a for a in runtime_art['assets']}
    for asset in read('assets/catalogue/provenance.json')['assets']:
        file(root, asset['source_path'], asset['source_sha256'])
        file(root, asset['runtime_path'], asset['runtime_sha256'])
        file(root, asset['prompt_path'])
        record = runtime_records[asset['runtime_path']]
        if (asset['source_path'] != record['original_path']
                or (asset['width'], asset['height']) != (record['width'], record['height'])):
            raise ValueError('Catalogue provenance differs from runtime manifest')
        for entry in asset['entries']:
            identity = entry['type_id']
            if identity in paintings:
                raise ValueError(f'Duplicate catalogue painting: {identity}')
            paintings.add(identity)
            x, y, width, height = entry['source_rect']
            if not (x >= 0 and y >= 0 and width > 0 and height > 0
                    and x + width <= asset['width'] and y + height <= asset['height']):
                raise ValueError(f'Invalid catalogue crop: {identity}')
    if paintings != required:
        raise ValueError(f'Missing or unexpected catalogue paintings: {sorted(paintings ^ required)}')

    ids = []
    atlases = set()
    for library, first, count in (('portraits-v2', 0, 250), ('portraits-v3', 250, 128),
                                  ('portraits-v4', 378, 1024)):
        metadata = read(f'assets/{library}/manifest.json')
        if (metadata['complete'] is not True or metadata['missingAtlases']
                or metadata['portraitCount'] != count):
            raise ValueError(f'Incomplete portrait library: {library}')
        assets = set()
        if library == 'portraits-v4' and metadata.get('unapprovedBatches'):
            raise ValueError('Portrait expansion contains unapproved artwork')
        for atlas in metadata['atlases']:
            if library == 'portraits-v4' and atlas.get('sourceReview') != 'passed':
                raise ValueError('Portrait expansion source review missing')
            file(root / 'assets' / library, atlas['source'], atlas['sourceSha256'])
            file(root / 'upstream', atlas['asset'], atlas['runtimeSha256'])
            assets.add(atlas['asset'])
            atlases.add(atlas['asset'])
            runtime_paths.add('upstream/' + atlas['asset'])
        portraits = metadata['portraits']
        if sorted(p['index'] for p in portraits) != list(range(first, first + count)):
            raise ValueError(f'Missing or duplicated portrait IDs: {library}')
        for portrait in portraits:
            if (portrait['asset'] not in assets
                    or portrait['id'] != f"portrait_{portrait['index']:03d}"):
                raise ValueError(f'Invalid portrait reference: {portrait}')
            ids.append(portrait['index'])
        overlay = metadata.get('appearanceOverlays')
        if overlay:
            file(root / 'assets' / library, overlay['source'], overlay['sourceSha256'])
            file(root / 'upstream', overlay['asset'], overlay['runtimeSha256'])
            runtime_paths.add('upstream/' + overlay['asset'])
    actual_paths = {path.relative_to(root).as_posix()
                    for path in (root / 'upstream/assets/modern').rglob('*')
                    if path.is_file() and path.suffix.lower() in {'.png', '.webp', '.jpg', '.jpeg'}}
    if actual_paths != runtime_paths:
        raise ValueError(f'Unexpected or missing runtime images: {sorted(actual_paths ^ runtime_paths)}')
    return {'status': 'passed', 'verified_files': len(checked),
            'runtime_images': len(runtime_paths), 'portrait_atlases': len(atlases),
            'portraits': len(ids), 'flag_assets': len(flag_assets),
            'catalogue_paintings': len(paintings), 'catalogue_exclusions': len(excluded)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    print(json.dumps(verify(parser.parse_args().root), indent=2))


if __name__ == '__main__':
    main()
