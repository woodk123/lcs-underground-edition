"""Shared runtime-art encoder. Install Pillow only when regenerating artwork."""
from __future__ import annotations

from pathlib import Path

from PIL import Image


RUNTIME_ENCODING = {
    'format': 'WebP', 'opaqueQuality': 90, 'transparentQuality': 90,
    'alpha': 'lossless', 'method': 6,
    'geometry': 'Unchanged dimensions, atlas cells and alpha; no palette reduction.',
}


def save_runtime_image(image: Image.Image, path: Path) -> None:
    """Compress colour at quality 90 while retaining exact alpha and geometry."""
    has_alpha = 'A' in image.getbands()
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format='WEBP', lossless=False,
               quality=RUNTIME_ENCODING['transparentQuality' if has_alpha else 'opaqueQuality'],
               alpha_quality=100, method=RUNTIME_ENCODING['method'], exact=True)
    with Image.open(path) as decoded:
        if decoded.size != image.size:
            raise ValueError(f'Runtime image dimensions changed: {path}')
        if has_alpha and decoded.convert('RGBA').getchannel('A').tobytes() != image.getchannel('A').tobytes():
            raise ValueError(f'Runtime image alpha changed: {path}')
