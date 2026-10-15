#!/usr/bin/env python3
"""Package 128 supplemental ImageGen portraits, preserving the original 250.

Only geometric crop, resize, and atlas operations are performed. Source images
are never edited. Run after all eight generated 4x4 source sheets are present.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont
from portrait_library import ROOT, digest, write_json

AGES = {16: [22, 30, 24, 45], 17: [25, 40, 55, 72],
        18: [25, 38, 53, 68], 19: [4, 7, 10, 12],
        20: [14, 16, 18, 19], 23: [76, 84, 92, 100]}
SPECIAL = (['tank'] * 2 + ['monster'] * 2 + ['purpleGorilla'] * 2 +
           ['warpedBear'] * 2 + ['pinkElephant'] * 2 + ['madCow'] * 2 +
           ['sixLeggedPig'] * 2 + ['flamingRabbit', 'giantMosquito'])
OVERLAYS = ['foreheadDressing', 'leftEyeDressing', 'rightEyeDressing',
            'noseDressing', 'helmet', 'mask', 'silverTemples', 'wrinkles',
            'labCoat', 'suit', 'workJacket', 'uniform', 'armor', 'robe',
            'casual', 'spareDressing']


def overlay_atlas(source: Path) -> tuple[Image.Image, dict] | None:
    path = source / 'appearance_overlays.png'
    if not path.is_file():
        return None
    with Image.open(path) as original:
        original.load()
        if original.format != 'PNG' or original.width != original.height or original.width < 1024:
            raise ValueError('Appearance overlays require square PNG >=1024px')
        if 'A' not in original.getbands():
            raise ValueError('Appearance overlays require genuine alpha transparency')
        image = original.convert('RGBA')
    alpha = image.getchannel('A')
    if alpha.getextrema() != (0, 255):
        raise ValueError('Appearance overlays must include transparent and opaque pixels')
    edges = [round(edge * image.width / 4) for edge in range(5)]
    runtime = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    entries = []
    for slot, name in enumerate(OVERLAYS):
        row, column = divmod(slot, 4)
        box = (edges[column], edges[row], edges[column + 1], edges[row + 1])
        cell = image.crop(box)
        # The source has near-invisible alpha speckles far outside each object.
        # Threshold determines the geometric crop only; pixels inside stay intact.
        bbox = cell.getchannel('A').point(lambda value: 255 if value > 16 else 0).getbbox()
        if bbox is None:
            raise ValueError(f'Appearance overlay cell {slot} is empty')
        crop = cell.crop(bbox)
        scale = min(252 / crop.width, 252 / crop.height)
        size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
        offset = (column * 256 + (256 - size[0]) // 2, row * 256 + (256 - size[1]) // 2)
        runtime.paste(crop.resize(size, Image.Resampling.LANCZOS), offset)
        histogram = cell.getchannel('A').histogram()
        entries.append({'index': slot, 'name': name, 'sourceRect': list(box),
                        'trimRectInCell': list(bbox), 'trimmedSize': list(crop.size),
                        'runtimeRect': [column * 256, row * 256, 256, 256],
                        'contentRect': [*offset, *size], 'cropSha256': digest(crop.tobytes()),
                        'alphaPixels': {'transparent': histogram[0], 'opaque': histogram[255],
                                        'partial': sum(histogram[1:255])}})
    return runtime, {'source': 'source/appearance_overlays.png',
                     'asset': 'assets/modern/portraits_v2/appearance_overlays.png',
                     'sourceSize': list(image.size), 'runtimeSize': [1024, 1024],
                     'sourceSha256': digest(path.read_bytes()),
                     'alphaRange': list(alpha.getextrema()), 'cropAlphaThreshold': 16,
                     'geometry': 'trim to alpha>16 bounding box; preserve RGBA within crop; fit252 and centre in256 cell',
                     'overlays': entries}


def background(batch: int, slot: int) -> str:
    if batch == 16:
        return ['punk', 'goth', 'emo', 'biker'][slot // 4]
    if batch == 22:
        return SPECIAL[slot]
    return {17: 'religious', 18: 'mutant', 19: 'child', 20: 'teenager',
            21: 'canine', 23: 'elderly'}[batch]


def contact_sheet(tiles: list[tuple[dict, Image.Image]], path: Path,
                  title: str | None = None) -> None:
    columns, size, footer, heading = 16, 96, 30, 38
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new('RGB', (columns * size, heading + rows * (size + footer)), '#eee8d8')
    draw, font = ImageDraw.Draw(sheet), ImageFont.load_default()
    draw.text((8, 12), title or f'Specialist portrait library: {len(tiles)} / 128; IDs 250-377', fill='#25251e', font=font)
    for position, (entry, crop) in enumerate(tiles):
        x, y = position % columns * size, heading + position // columns * (size + footer)
        sheet.paste(crop.resize((size, size), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 2, y + size + 2), f'{entry["index"]:03} {entry["presentation"][0].upper()} age {entry["visualAge"]}', fill='#25251e', font=font)
        draw.text((x + 2, y + size + 15), entry['professionGroup'], fill='#25251e', font=font)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def build(source: Path, output: Path, review: Path, partial: bool) -> dict:
    missing = [f'batch_{batch:02}.png' for batch in range(16, 24)
               if not (source / f'batch_{batch:02}.png').is_file()]
    if missing and not partial:
        raise ValueError('Missing sources: ' + ', '.join(missing))
    overlays = overlay_atlas(source)
    entries, atlases, tiles, prepared = [], [], [], []
    seen, source_seen = {}, {}
    # Also reject exact copies of the shipped library's source crops/sheets.
    old = json.loads((ROOT / 'assets/portraits-v2/manifest.json').read_text(encoding='utf-8'))
    for entry in old['portraits']:
        seen[entry['cropSha256']] = entry['index']
    for entry in old['atlases']:
        source_seen[entry['sourceSha256']] = entry['batch']
    for batch in range(16, 24):
        path = source / f'batch_{batch:02}.png'
        if not path.is_file():
            continue
        with Image.open(path) as original:
            original.load()
            if original.format != 'PNG' or original.width != original.height or original.width < 1024:
                raise ValueError(f'{path.name}: expected square PNG at least 1024 pixels wide')
            width, height = original.size
            image = original.convert('RGB')
        source_hash = digest(path.read_bytes())
        if source_hash in source_seen:
            raise ValueError(f'{path.name}: duplicates source batch {source_seen[source_hash]}')
        source_seen[source_hash] = batch
        edges = [round(edge * width / 4) for edge in range(5)]
        runtime = Image.new('RGB', (1024, 1024))
        for slot in range(16):
            row, column = divmod(slot, 4)
            x, y, right, bottom = edges[column], edges[row], edges[column + 1], edges[row + 1]
            crop = image.crop((x, y, right, bottom))
            crop_hash = digest(crop.tobytes())
            index = 250 + (batch - 16) * 16 + slot
            if crop_hash in seen:
                raise ValueError(f'Portrait {index} duplicates crop {seen[crop_hash]}')
            seen[crop_hash] = index
            runtime.paste(crop.resize((256, 256), Image.Resampling.LANCZOS), (column * 256, row * 256))
            age = AGES.get(batch, [0] * 4)[row]
            entry = {'id': f'portrait_{index:03}', 'index': index, 'batch': batch,
                     'asset': f'assets/modern/portraits_v2/{path.name}',
                     'row': row, 'column': column, 'professionGroup': background(batch, slot),
                     'presentation': ('female' if column % 2 == 0 else 'male') if batch not in (21, 22) else 'unspecified',
                     'visualAge': age, 'ageMin': age, 'ageMax': age,
                     'rect': [column * 256, row * 256, 256, 256],
                     'sourceRect': [x, y, right - x, bottom - y], 'cropSha256': crop_hash}
            if batch == 17:
                entry['artDirection'] = 'nun/religious woman' if column % 2 == 0 else 'priest/pastor'
            entries.append(entry)
            tiles.append((entry, crop))
        atlases.append({'batch': batch, 'source': f'source/{path.name}',
                        'asset': f'assets/modern/portraits_v2/{path.name}',
                        'sourceSize': [width, height], 'runtimeSize': [1024, 1024],
                        'validPortraits': 16, 'sourceSha256': source_hash})
        prepared.append((path.name, runtime))
    manifest = {'version': 3, 'portraitCount': len(entries), 'firstId': 250, 'lastId': 377,
                'basePortraitCount': 250, 'combinedPortraitCount': 250 + len(entries),
                'gridColumns': 4, 'gridRows': 4, 'runtimeAtlasSize': 1024,
                'complete': not missing, 'missingAtlases': missing,
                'counts': {'professionGroup': dict(Counter(e['professionGroup'] for e in entries)),
                           'presentation': dict(Counter(e['presentation'] for e in entries))},
                'atlases': atlases, 'portraits': entries,
                'validation': {'duplicateCrops': [], 'visualReviewRequired': True,
                               'geometry': 'shared rounded quarter boundaries; individual cell resizing; no retouching'}}
    if overlays is not None:
        manifest['appearanceOverlays'] = overlays[1]
    if tiles:
        contact_sheet(tiles, review / ('overview-partial.png' if partial else 'overview.png'))
    if not partial:
        combined = []
        for atlas in old['atlases']:
            with Image.open(ROOT / 'assets/portraits-v2' / atlas['source']) as original:
                original.load()
                for entry in old['portraits']:
                    if entry['batch'] != atlas['batch']:
                        continue
                    x, y, width, height = entry['sourceRect']
                    combined.append(({**entry, 'visualAge': [25, 38, 53, 68][entry['row']]},
                                     original.convert('RGB').crop((x, y, x + width, y + height))))
        contact_sheet(combined + tiles, review / 'overview-all-378.png',
                      'Complete painted portrait library: 378 portraits; labels outside portraits; age is approximate art direction')
    if partial:
        write_json(review / 'validation-partial.json', manifest)
    else:
        if len(entries) != 128:
            raise ValueError('Expected exactly 128 supplemental portraits')
        output.mkdir(parents=True, exist_ok=True)
        for name, atlas in prepared:
            atlas.save(output / name, optimize=True)
        if overlays is not None:
            overlays[0].save(output / 'appearance_overlays.png', optimize=True)
            overlays[1]['runtimeSha256'] = digest((output / 'appearance_overlays.png').read_bytes())
        for atlas in atlases:
            atlas['runtimeSha256'] = digest((output / Path(atlas['asset']).name).read_bytes())
        write_json(review / 'manifest.json', manifest)
        write_json(output / 'manifest-v3.json', manifest)
    return {'portraitCount': len(entries), 'complete': not missing, 'runtimeWritten': not partial,
            'review': str(review), 'counts': manifest['counts']}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'assets/portraits-v3/source')
    parser.add_argument('--output', type=Path, default=ROOT / 'upstream/assets/modern/portraits_v2')
    parser.add_argument('--review', type=Path, default=ROOT / 'assets/portraits-v3')
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.source, args.output, args.review, args.partial), indent=2))
    except (ValueError, OSError) as error:
        print(f'Specialist portrait validation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
