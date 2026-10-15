"""Regenerate static WebP art from the full-quality, source-only PNG masters."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from release_common import digest, write_json
from runtime_images import RUNTIME_ENCODING, save_runtime_image


def build(root: Path) -> dict:
    sources = sorted((root / 'assets/runtime-art/source').glob('*.png'))
    if not sources:
        raise ValueError('No original artwork found under assets/runtime-art/source')
    records = []
    for source in sources:
        runtime = root / 'upstream/assets/modern' / (source.stem + '.webp')
        with Image.open(source) as image:
            save_runtime_image(image, runtime)
            record = {'original_path': source.relative_to(root).as_posix(),
                      'runtime_path': runtime.relative_to(root).as_posix(),
                      'width': image.width, 'height': image.height, 'mode': image.mode,
                      'lossless': 'A' in image.getbands()}
        record.update(original_sha256=digest(source), runtime_sha256=digest(runtime),
                      original_bytes=source.stat().st_size, runtime_bytes=runtime.stat().st_size)
        records.append(record)
    write_json(root / 'assets/runtime-art/manifest.json',
               {'version': 1, 'encoding': RUNTIME_ENCODING, 'assets': records})
    by_stem = {Path(record['original_path']).stem: record for record in records}
    for relative in ('assets/art-city-v2/atlas_metadata.json',
                     'assets/gangsters-journal/atlas_metadata.json'):
        path = root / relative
        metadata = json.loads(path.read_text(encoding='utf-8'))
        metadata['postprocessing'] = ('Runtime WebP copies use scripts/build_runtime_art.py; '
                                      'PNG masters, dimensions and crop rectangles are preserved.')
        for asset in metadata['assets'].values():
            record = by_stem[Path(asset['runtime_path']).stem]
            asset.update(original_path=record['original_path'], runtime_path=record['runtime_path'],
                         sha256=record['original_sha256'], runtime_sha256=record['runtime_sha256'])
        write_json(path, metadata)
    return {'images': len(records), 'original_bytes': sum(r['original_bytes'] for r in records),
            'runtime_bytes': sum(r['runtime_bytes'] for r in records), 'encoding': RUNTIME_ENCODING}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    print(json.dumps(build(parser.parse_args().root.resolve()), indent=2))
