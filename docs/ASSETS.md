# Artwork and assets

Production art, fonts and application icons live under `upstream/assets/`, `upstream/fonts/`, and the platform/web resource directories. Those are the files Flutter builds. Original game data, maps and licenses remain in the upstream tree.

The journal materials, painted portraits and map illustrations were generated for this project with AI assistance. Prompts and provenance are kept under root `assets/`. No original Gangsters bitmap is shipped; its organiser inspired the layout.

## Authoritative copies

- `upstream/assets/modern/` contains compressed WebP runtime illustrations, textures, atlases and renderer metadata. All artwork uses quality 90 colour compression with pixel-exact lossless alpha. Dimensions and atlas cells are preserved.
- `assets/runtime-art/source/` retains the original static PNGs. `assets/runtime-art/manifest.json` records their source/runtime hashes, geometry and encoding policy. These originals are included in Source ZIPs only.
- `assets/art-city-v2/atlas_metadata.json` and `assets/gangsters-journal/atlas_metadata.json` record the selected files, prompts, source/runtime hashes and crop geometry. Their paths are repository-relative.
- `assets/art/` retains the prompts for current district/site art.
- `activist_crew_v1` supplies the crew/personnel illustration across the title, creation and journal screens. Its source PNG and generation prompt are retained with the other static art.
- `journal_network_emblem_v1` supplies the Network tab's paired undercover figures, and `journal_network_empty_v1` supplies its empty-directory vignette. Their transparent PNG masters use the normal static-art pipeline; [prompts and provenance](../assets/network/provenance.json) accompany both assets. Labels and review counts remain live Flutter text.
- `journal_operations_icons_v1` supplies six management sprites: People, Bases, Stores, Leadership, Captives and Media. Its transparent 1536×1024 PNG master uses a row-major 3×2 grid of 512×512 cells and builds to `upstream/assets/modern/journal_operations_icons_v1.webp` through the static-art pipeline. [Prompts, cell geometry and provenance](../assets/operations/provenance.json) record the selected generation and spacing edit. Counts, warnings and controls remain live Flutter widgets.
- `journal_equipment_weapons_v1`, `journal_equipment_gear_v1` and `journal_vehicles_v1` supply 32 equipment paintings and all 11 vehicle catalogue types. The transparent 1536×1024 PNG masters use inspected full-object crops, rather than equal-cell cuts, and build through the static-art pipeline. [Prompts, exact type IDs, crops and provenance](../assets/catalogue/provenance.json) accompany the art. Equipment, shop and selective-sale rows, personnel dossiers and comparison guides consume these pictures. Vehicle purchase choices attach type-only metadata without creating a vehicle or rolling its year/colour. Unsupported equipment retains its original text. Pictures describe catalogue types; quantities, condition, armour, vehicle colour/year, prices and controls remain live game data.
- Eight `journal_catalogue_*_v1` supplemental atlases complete all 145 tangible equipment types with 113 additional paintings (25 weapons, 53 outfits, 7 ammunition types and 28 loot items). The [coverage audit](ASSET_COVERAGE.md) lists every original gap and the five intentional absence/body-attack exclusions. Generated RGBA masters are retained unchanged; each exact ID has its own inspected full-object crop, including detached parts. [Coverage requirements](../assets/catalogue/coverage.json), prompts and provenance are checked against the authored XML catalogues. Regenerate supplemental WebP files, manifest records and Dart mappings with `python scripts/build_catalogue_art.py --encode`; omit `--encode` to export metadata/mappings from already encoded files. This touches only supplemental art. Keep installed armor and condition in live text, separate from type illustrations.
- `injury_anatomy_front_v1` is the transparent front-view medical engraving in personnel dossiers. [Its generation prompt and landmarks](../assets/injury-status/provenance.json) accompany the PNG master. Flutter draws the injury overlays, callouts and labels; `injury_anatomy.dart` traces the selected image so visual highlights and pointer targets share the same geometry.
- `tactical_terrain_v1`, `tactical_objects_v1` and `tactical_hazards_v1` supply the field plan and full-floor map. The 4×4 terrain and object sheets are 1254×1254; the 4×2 hazard sheet is 1774×887. [Generation prompts and row-major cell mappings](../assets/tactical/provenance.json) accompany the source PNGs. `tactical_art.dart` uses fractional, inset crop rectangles and the shared image cache. Runtime art adds 1,661,332 bytes. Doors, exits, stairs, unit tokens, fog and movement cues remain resolution-independent Canvas artwork in `tactical_symbols.dart` and `tactical_map.dart`. Floor and wall materials are decorative choices based on site type; object sprites correspond to existing known specials, loot and hazards. Hidden tiles carry no sprite metadata.
- `tactical_objects_extra_v1` adds 16 fixtures for detention and patient rooms, offices, banks, the jury room, signs, broadcasting, computing, textiles, reactor/prison controls, armories and insurance claims. The transparent 1254×1254 master retains the generated image unchanged; inspected square crops center each object independently of the generated grid. [Exact prompts and crop geometry](../assets/tactical/supplemental-prompts.json) accompany the source. Original object IDs 0–15 are preserved; supplemental IDs 16–31 are shared by the local map, full-floor map, inspectors and map key. The four Oval Office tiles draw quadrants of one desk. Sign markers, faction graffiti and the visited-patient check remain live Canvas artwork; the original sign reader supplies the wording. Badges preserve fire, trap and unit cues, and unknown tiles receive no supplemental metadata.
- `assets/portraits-v2/`, `assets/portraits-v3/` and `assets/portraits-v4/` retain original portrait sheets, prompts and full manifests. These originals differ from the cropped/resized runtime atlases and are needed for regeneration. The v4 expansion also records independently reviewed crop boundaries and source hashes for its 1,024 appended identities.

Rejected drafts, partial validations and generated contact sheets are not tracked. Historical edit inputs use `git:<commit>:<path>` references where needed. Asset-review helpers write their review output under `.local/art-review/` by default. Do not renumber shipped atlas cells: saved characters reference portrait IDs. See [PORTRAIT_LIBRARY.md](PORTRAIT_LIBRARY.md) for the mapping.

Already-created dropped loot reuses catalogue paintings on the local and full-floor tactical maps. Single-type piles show their item artwork; mixed or unsupported piles retain a crate, with a badge counting actual dropped stacks. Tile details show frozen item titles, quantities and thumbnails. Unsearched tile loot has no item identity until the original search handler rolls it, so it stays generic and contributes no invented count. These previews neither create items nor change pickup rules.

## Editing and validation

Keep labels, statistics and controls in Flutter; artwork supplies visual material only. City geometry is illustrative, not a source of gameplay travel rules. Overlay geometry must match the selected atlas and retain transparency.

```powershell
python scripts/verify_assets.py
```

This checks manifest paths, source/runtime hashes, portrait counts and IDs, and rejects unlisted or duplicate runtime image files. It also checks the flag catalogue in `upstream/assets/xml/flags.xml`: each declared asset must exist, and every shipped flag SVG must be listed. Add or remove a flag's catalogue entry and SVG together.

Release builds use the checked-in WebP files and do not need Pillow. Flutter tests decode every runtime atlas with the native image codec, check exact alpha against the transparent static PNG masters, and bound mean squared native colour error to 100 (RMS error at most 10 levels out of 255). The encoder also verifies exact alpha and unchanged dimensions. Colour is lossy; inspect visual comparisons when changing the encoding policy.

The quality 90 policy was selected on 17 October 2026 after source-based comparisons at qualities 90, 85 and 80. All 42 regenerated images matched the reviewed quality 90 candidates. Runtime image bytes dropped by 45.8%, without resizing or changing atlas layout. See [measured player sizes and validation](BUILDING.md#quality-90-size-measurements-17-october-2026) for the rebuilt ZIP results and verification scope.

To regenerate static runtime art, install `scripts/requirements-art.txt`, then run:

```powershell
python scripts/build_runtime_art.py
python scripts/verify_assets.py
```

For portraits, follow [the portrait workflow](PORTRAIT_LIBRARY.md). Both generators use `scripts/runtime_images.py`; always encode from the original PNGs to avoid accumulating lossy changes. `portrait_face_frames.py` additionally needs `opencv-python-headless<5`; `portrait_overlay_geometry.py` derives the overlay rectangles. `export_app_mark.py` exports the authored SVG app mark to platform icons, and `generate_location_catalog.py` regenerates location-help metadata from the game data.

Font licenses and component notices travel with player packages. Runtime images are never removed just because a source/reference copy has been consolidated.
