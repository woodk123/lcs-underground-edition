# Artwork and assets

Production art, fonts and application icons live under `upstream/assets/`, `upstream/fonts/`, and the platform/web resource directories. Those are the files Flutter builds. Original game data, maps and licenses remain in the upstream tree.

The journal materials, painted portraits and map illustrations were generated for this project with AI assistance. Prompts and provenance are kept under root `assets/`. No original Gangsters bitmap is shipped; its organiser inspired the layout.

## Authoritative copies

- `upstream/assets/modern/` contains compressed WebP runtime illustrations, textures, atlases and renderer metadata. Opaque paintings use quality 95; transparent artwork uses pixel-exact lossless encoding. Dimensions and atlas cells are preserved.
- `assets/runtime-art/source/` retains the original static PNGs. `assets/runtime-art/manifest.json` records their source/runtime hashes, geometry and encoding policy. These originals are included in Source ZIPs only.
- `assets/art-city-v2/atlas_metadata.json` and `assets/gangsters-journal/atlas_metadata.json` record the selected files, prompts, source/runtime hashes and crop geometry. Their paths are repository-relative.
- `assets/art/` retains the prompts for current district/site art.
- `activist_crew_v1` supplies the crew/personnel illustration across the title, creation and journal screens. Its source PNG and generation prompt are retained with the other static art.
- `assets/portraits-v2/` and `assets/portraits-v3/` retain original portrait sheets, prompts and full manifests. These originals differ from the cropped/resized runtime atlases and are needed for regeneration.

Rejected drafts, partial validations and generated contact sheets are not tracked. Historical edit inputs use `git:<commit>:<path>` references where needed. Asset-review helpers write their review output under `.local/art-review/` by default. Do not renumber shipped atlas cells: saved characters reference portrait IDs. See [PORTRAIT_LIBRARY.md](PORTRAIT_LIBRARY.md) for the mapping.

## Editing and validation

Keep labels, statistics and controls in Flutter; artwork supplies visual material only. City geometry is illustrative, not a source of gameplay travel rules. Overlay geometry must match the selected atlas and retain transparency.

```powershell
python scripts/verify_assets.py
```

This checks manifest paths, source/runtime hashes, portrait counts and IDs, and rejects unlisted or duplicate runtime image files. Release builds use the checked-in WebP files and do not need Pillow. Flutter tests decode every runtime atlas with the native image codec and check exact alpha against the static PNG masters, allowing at most one RGB level for native premultiplication rounding. The encoder also verifies exact straight-RGBA pixels for all transparent artwork.

To regenerate static runtime art, install `scripts/requirements-art.txt`, then run:

```powershell
python scripts/build_runtime_art.py
python scripts/verify_assets.py
```

For portraits, follow [the portrait workflow](PORTRAIT_LIBRARY.md). Both generators use `scripts/runtime_images.py`; always encode from the original PNGs to avoid accumulating lossy changes. `portrait_face_frames.py` additionally needs `opencv-python-headless<5`; `portrait_overlay_geometry.py` derives the overlay rectangles. `export_app_mark.py` exports the authored SVG app mark to platform icons, and `generate_location_catalog.py` regenerates location-help metadata from the game data.

Font licenses and component notices travel with player packages. Runtime images are never removed just because a source/reference copy has been consolidated.
