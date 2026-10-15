"""Shared runtime-art encoder. Install Pillow only when regenerating artwork."""
from __future__ import annotations

from pathlib import Path

from PIL import Image


RUNTIME_ENCODING = {
    'format': 'WebP', 'opaqueQuality': 95, 'alpha': 'lossless', 'method': 6,
    'geometry': 'Unchanged dimensions, atlas cells and alpha; no palette reduction.',
}


def save_runtime_image(image: Image.Image, path: Path) -> None:
    """Preserve exact transparent pixels; use conservative compression otherwise."""
    lossless = 'A' in image.getbands()
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format='WEBP', lossless=lossless,
               quality=100 if lossless else RUNTIME_ENCODING['opaqueQuality'],
               method=RUNTIME_ENCODING['method'], exact=True)
    with Image.open(path) as decoded:
        if decoded.size != image.size:
            raise ValueError(f'Runtime image dimensions changed: {path}')
        if lossless and decoded.convert('RGBA').tobytes() != image.convert('RGBA').tobytes():
            raise ValueError(f'Lossless runtime image pixels changed: {path}')
