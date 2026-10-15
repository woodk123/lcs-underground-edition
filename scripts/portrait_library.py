#!/usr/bin/env python3
"""Validate generated 4x4 portrait sheets and package the approved 250 cells.

Only image geometry operations are performed. Original generation files are never
modified. Pillow is required: python -m pip install Pillow.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
GROUPS = (["professional"] * 3 + ["trades"] * 3 +
          ["academicMedical"] * 2 + ["streetCreative"] * 3 +
          ["securityMilitary"] * 2 + ["civilian"] * 3)
AGES = [(20, 30), (30, 45), (45, 60), (60, 75)]
COUNT = 250
GRID = 4


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def overview(tiles: list[tuple[dict, Image.Image]], output: Path) -> None:
    """Labels occupy their own footer, never the portrait itself."""
    columns, cell, footer, heading = 16, 96, 28, 36
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, heading + rows * (cell + footer)), "#eee8d8")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    draw.text((8, 10), f"Portrait library: {len(tiles)} portraits / 250; labels are below each tile", fill="#25251e", font=font)
    for position, (entry, portrait) in enumerate(tiles):
        x, y = (position % columns) * cell, heading + (position // columns) * (cell + footer)
        sheet.paste(portrait.resize((cell, cell), Image.Resampling.LANCZOS), (x, y))
        short_group = {"professional": "office", "academicMedical": "academic/med", "streetCreative": "street/art", "securityMilitary": "security"}.get(entry["professionGroup"], entry["professionGroup"])
        draw.text((x + 3, y + cell + 2), f'{entry["index"]:03} {entry["presentation"][0].upper()} {entry["ageMin"]}-{entry["ageMax"]}', fill="#25251e", font=font)
        draw.text((x + 3, y + cell + 14), short_group, fill="#25251e", font=font)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def build(source: Path, output: Path, review: Path, atlas_size: int, partial: bool, manifest_path: Path | None = None) -> dict:
    if atlas_size <= 0 or atlas_size % GRID:
        raise ValueError("--atlas-size must be positive and divisible by 4")
    missing = [f"batch_{batch:02}.png" for batch in range(16)
               if not (source / f"batch_{batch:02}.png").is_file()]
    if missing and not partial:
        raise ValueError("Missing source atlases: " + ", ".join(missing) + ". Use --partial for source-only QA.")
    entries, atlases, tiles, prepared = [], [], [], []
    seen: dict[str, int] = {}
    source_seen: dict[str, int] = {}
    duplicates = []
    runtime_cell = atlas_size // GRID
    for batch in range(16):
        path = source / f"batch_{batch:02}.png"
        if not path.is_file():
            continue
        with Image.open(path) as original:
            original.load()
            if original.format != "PNG":
                raise ValueError(f"{path.name}: source must be PNG")
            width, height = original.size
            if width != height:
                raise ValueError(f"{path.name}: expected square dimensions, got {width}x{height}")
            if width < atlas_size:
                raise ValueError(f"{path.name}: {width}px source is smaller than {atlas_size}px runtime target; refusing to upscale")
            image = original.convert("RGB")
        source_hash = digest(path.read_bytes())
        if source_hash in source_seen:
            raise ValueError(f"{path.name}: duplicates complete batch {source_seen[source_hash]:02}")
        source_seen[source_hash] = batch
        # Generated sheets can have dimensions such as 1254px. Shared rounded
        # boundaries partition all pixels exactly once without discarding edges.
        source_edges = [round(edge * width / GRID) for edge in range(GRID + 1)]
        runtime = Image.new("RGB", (atlas_size, atlas_size))
        valid = min(16, COUNT - batch * 16)
        # Resize each crop independently so filtering cannot blend neighbouring faces.
        for slot in range(16):
            row, column = divmod(slot, GRID)
            x, y = source_edges[column], source_edges[row]
            right, bottom = source_edges[column + 1], source_edges[row + 1]
            crop = image.crop((x, y, right, bottom))
            runtime.paste(crop.resize((runtime_cell, runtime_cell), Image.Resampling.LANCZOS),
                          (column * runtime_cell, row * runtime_cell))
            if slot >= valid:
                continue
            index = batch * 16 + slot
            crop_hash = digest(crop.tobytes())
            if crop_hash in seen:
                duplicates.append([seen[crop_hash], index])
            seen[crop_hash] = index
            age_min, age_max = AGES[row]
            entry = {"id": f"portrait_{index:03}", "index": index, "batch": batch,
                     "asset": f"assets/modern/portraits_v2/batch_{batch:02}.png",
                     "row": row, "column": column, "professionGroup": GROUPS[batch],
                     "presentation": "female" if column % 2 == 0 else "male",
                     "ageMin": age_min, "ageMax": age_max,
                     "rect": [column * runtime_cell, row * runtime_cell, runtime_cell, runtime_cell],
                     "sourceRect": [x, y, right - x, bottom - y], "cropSha256": crop_hash}
            entries.append(entry)
            tiles.append((entry, crop))
        atlases.append({"batch": batch, "source": f"source/{path.name}",
                        "asset": f"assets/modern/portraits_v2/{path.name}",
                        "sourceSize": [width, height], "runtimeSize": [atlas_size, atlas_size],
                        "validPortraits": valid, "sourceSha256": source_hash})
        prepared.append((path.name, runtime))
    if duplicates:
        raise ValueError(f"Exact duplicate portrait crops: {duplicates}")
    if not partial and (len(entries) != COUNT or len({e['id'] for e in entries}) != COUNT):
        raise ValueError("Complete manifest must contain exactly 250 distinct entries")
    manifest = {"version": 2, "portraitCount": len(entries), "gridColumns": GRID,
                "gridRows": GRID, "runtimeAtlasSize": atlas_size,
                "complete": not missing, "missingAtlases": missing,
                "counts": {"professionGroup": dict(Counter(e["professionGroup"] for e in entries)),
                           "presentation": dict(Counter(e["presentation"] for e in entries))},
                "atlases": atlases, "portraits": entries,
                "validation": {"duplicateCrops": duplicates,
                               "geometry": "square 4x4; shared rounded source boundaries partition every pixel; exact runtime cells; no added padding",
                               "visualReviewRequired": True}}
    if tiles:
        overview(tiles, review / ("overview-partial.png" if partial else "overview.png"))
    if partial:
        write_json(review / "validation-partial.json", manifest)
    else:
        output.mkdir(parents=True, exist_ok=True)
        for name, atlas in prepared:
            atlas.save(output / name, optimize=True)
        for atlas in manifest["atlases"]:
            atlas["runtimeSha256"] = digest((output / Path(atlas["asset"]).name).read_bytes())
        write_json(output / "manifest.json", manifest)
        write_json(manifest_path or review / "manifest.json", manifest)
    return {"portraitCount": len(entries), "atlasCount": len(atlases),
            "complete": not missing, "partialMode": partial, "counts": manifest["counts"],
            "review": str(review), "runtimeWritten": not partial}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "assets/portraits-v2/source")
    parser.add_argument("--output", type=Path, default=ROOT / "upstream/assets/modern/portraits_v2")
    parser.add_argument("--review", type=Path, default=ROOT / ".local/art-review/portraits-v2")
    parser.add_argument("--manifest", type=Path, default=ROOT / "assets/portraits-v2/manifest.json")
    parser.add_argument("--atlas-size", type=int, default=1024)
    parser.add_argument("--partial", action="store_true", help="QA available source files; never publish runtime assets")
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.source, args.output, args.review, args.atlas_size, args.partial, args.manifest), indent=2))
    except (ValueError, OSError) as error:
        print(f"Portrait library validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
