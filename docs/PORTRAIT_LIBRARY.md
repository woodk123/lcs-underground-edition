# Portrait library

The library has **378 saved identities**: 250 ordinary adults and 128 specialist/age/body portraits. The paintings use approximate age cues; character age comes from the save, not the image.

## Files and IDs

Original PNG sheets and prompts are under `assets/portraits-v2/` and `assets/portraits-v3/`. Their full manifests record source/runtime hashes and crop rectangles. Runtime WebP atlases are `upstream/assets/modern/portraits_v2/`: quality 90 colour for paintings and appearance overlays, with pixel-exact lossless alpha. Each portrait remains in its original 256px cell; saved IDs and crop geometry are unchanged.

| IDs | Source batches | Contents |
|---|---|---|
| 0–249 | 00–15 | Ordinary adults; the last sheet has ten used cells |
| 250–265 | 16 | Punk, goth, emo and biker |
| 266–281 | 17 | Religious professions |
| 282–297 | 18 | Mutants |
| 298–313 | 19 | Children |
| 314–329 | 20 | Teenagers and young adults |
| 330–345 | 21 | Dogs |
| 346–361 | 22 | Vehicles and other creatures |
| 362–377 | 23 | Elderly adults |

Preserve these IDs and append new art rather than inserting it. Base IDs use `batch = id ~/ 16`, `cell = id % 16`; specialist IDs use `batch = 16 + (id - 250) ~/ 16`, `cell = (id - 250) % 16`. Human columns alternate presentation; nonhuman casting ignores gender.

## Casting and persistence

`upstream/lib/creature/portrait.dart` chooses from a suitable age pool before considering profession or unused faces. Adults under 30 stay within eight painted years, older adults within twelve. Children/teenagers have dedicated age pools. Reuse a suitable face before using an older unused one; cosmetic variants distinguish repeated portraits. If a human specialist bank lacks a suitable age, use an ordinary age-compatible face. Mutants and nonhuman bodies retain compatible artwork, using the nearest available age where necessary.

`portraitId`, `portraitAssignedAge` and `portraitVariant` are persisted. Check saved faces against age at assignment so birthdays do not reroll an appropriate identity. Clearly mismatched older assignments are repaired once. Casting uses isolated deterministic randomness and must never advance gameplay RNG.

Rendering lives in `modern/crew_portrait.dart`. Supported equipment, injuries and ageing use overlays without rerolling the face; the dossier remains the authoritative medical/equipment record.

The founder identity page offers a portrait preview and **Reroll portrait** (`F`) beside the name controls. Options follow the starting campaign age and selected presentation. Cycling uses an isolated seed/catalog order and leaves names, stats, campaign state and gameplay RNG alone. The chosen face and its original assignment age carry through backgrounds, headquarters and save/reload. Do not overwrite the assignment age after a birthday: doing so can recast a face at the edge of its cohort. Clothing overlays can change with equipment while the face remains fixed. Decorative crew/personnel icons use a separate activist-group illustration and do not assign character identities.

## Regenerate

Install the regeneration dependency with `python -m pip install -r scripts/requirements-art.txt`. From the repository root:

```powershell
python scripts/portrait_library.py --partial
python scripts/specialist_portrait_library.py --partial
```

Partial mode validates available sources and writes contact sheets/reports under ignored `.local/art-review/`; it does not publish runtime atlases. Inspect presentation, age cues, crops and duplicates visually—hashes cannot certify an image's visual meaning.

After approving the art, run both commands without `--partial` to publish runtime atlases and refresh the versioned full manifests. Use `--review` to choose another review-output directory and `--manifest` to choose a metadata destination.

If face or overlay geometry changed, regenerate with `portrait_face_frames.py` and `portrait_overlay_geometry.py`, then run:

```powershell
python scripts/verify_assets.py
Set-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub test/portrait_library_test.dart test/portrait_appearance_test.dart test/crew_dossier_test.dart
```

Never change an existing atlas slot to an unrelated face without a deliberate save-migration policy.
