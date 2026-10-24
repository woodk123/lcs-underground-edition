# Portrait library

The library has **1,402 saved identities**: the original 378 plus an append-only expansion of 1,024. The expansion adds 640 ordinary adults, 192 profession/subculture portraits, 96 children/teenagers, 64 elderly adults and 32 mutants/dogs. The paintings use approximate age cues; character age comes from the save, not the image.

## Files and IDs

Original PNG sheets and prompts are under `assets/portraits-v2/`, `assets/portraits-v3/` and `assets/portraits-v4/`. Their full manifests record source/runtime hashes and crop rectangles. Runtime WebP atlases are `upstream/assets/modern/portraits_v2/`: quality 90 colour for paintings and appearance overlays, with pixel-exact lossless alpha. Each portrait occupies a 256px cell; the original 378 IDs and crop geometry are unchanged. Expansion sources have individually reviewed row boundaries recorded in `crop-overrides.json`, avoiding adjacent-row strips in otherwise uneven generated sheets.

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
| 378–1017 | 24–63 | Ordinary adult civilian, office, trade, academic and creative banks |
| 1018–1209 | 64–75 | Subcultures, religious, security, office and creative professions |
| 1210–1257 | 76–78 | Children |
| 1258–1305 | 79–81 | Teenagers and young adults |
| 1306–1369 | 82–85 | Elderly adults |
| 1370–1385 | 86 | Mutants |
| 1386–1401 | 87 | Dogs |

Preserve these IDs and append new art rather than inserting it. Base IDs use `batch = id ~/ 16`, `cell = id % 16`; specialist IDs use `batch = 16 + (id - 250) ~/ 16`, `cell = (id - 250) % 16`. Human columns alternate presentation; nonhuman casting ignores gender.

## Casting and persistence

`upstream/lib/creature/portrait.dart` chooses from a suitable age pool before considering profession or unused faces. Adults under 30 stay within eight painted years, older adults within twelve. Children/teenagers have dedicated age pools. Reuse a suitable face before using an older unused one; cosmetic variants distinguish repeated portraits. If a human specialist bank lacks a suitable age, use an ordinary age-compatible face. Mutants and nonhuman bodies retain compatible artwork, using the nearest available age where necessary.

`portraitId`, `portraitAssignedAge` and `portraitVariant` are persisted. Check saved faces against age at assignment so birthdays do not reroll an appropriate identity. Clearly mismatched older assignments are repaired once. Casting uses isolated deterministic randomness and must never advance gameplay RNG.

Rendering lives in `modern/crew_portrait.dart`. Supported equipment, injuries and ageing use overlays without rerolling the face; the dossier remains the authoritative medical/equipment record.

The founder identity page offers a portrait preview with **Select portrait** (`G`) and **Reroll portrait** (`F`) beside the name controls. Options follow the starting campaign age and selected presentation. The gallery shows twelve compatible faces per page with A–L selection, N/P paging and Escape to return without changing the face. Selecting a face returns to identity; reopening starts on the current face’s page. Cycling uses an isolated seed/catalog order and leaves names, stats, campaign state and gameplay RNG alone. The chosen face and its original assignment age carry through backgrounds, headquarters and save/reload. Do not overwrite the assignment age after a birthday: doing so can recast a face at the edge of its cohort. Clothing overlays can change with equipment while the face remains fixed. Decorative crew/personnel icons use a separate activist-group illustration and do not assign character identities.

## Regenerate

Install the regeneration dependency with `python -m pip install -r scripts/requirements-art.txt`. From the repository root:

```powershell
python scripts/portrait_library.py --partial
python scripts/specialist_portrait_library.py --partial
python scripts/expanded_portrait_library.py --partial --runtime-review
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

The expansion packager requires every source PNG hash, both crop-edge arrays and the saved-ID/role/age signature to match independent passed source-art review. Initial publication uses `--approvals .local/art-review/portraits-v4/source-approvals.json`; subsequent regeneration without that option uses the reviewed hashes/edges/signatures retained in `assets/portraits-v4/manifest.json`. New or changed sources or casting metadata cannot inherit an old approval. Partial mode with `--runtime-review` encodes only ignored WebP previews; it never publishes runtime assets. `prompts.json` is the recorded generation brief, with follow-up edits in `prompt-overrides.json`; the planning script refuses to overwrite it.

For a new expansion, use `portrait_face_frames.py --append-expansion` after packaging to detect its human frames while retaining every original frame. Nonhuman cells are excluded using the expansion manifest. The detector requires `opencv-python-headless<5`; missing face detections remain omitted rather than guessed.

`portrait_expansion_render_test.dart` decodes every new runtime atlas and writes actual native renders under `reports/portraits-v4/appearance/`. Columns show plain art, head/left-eye dressings, right-eye/nose dressings, medical clothing, armour/helmet, uniform/mask and ageing. Four diagonal cells per atlas cover all age rows and both presentations. Source-art approval, runtime/overlay review and integrated browser acceptance are separate evidence; a source pass alone is not final acceptance.
