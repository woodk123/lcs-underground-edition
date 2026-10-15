# Painted portrait library

The base portrait library contains 250 painted portraits in sixteen 4Ã—4 atlases.
Image generation supplies complete painted portraits. The game selects a saved
portrait identity using broad profession, presentation and age pools. Skills do
not determine facial anatomy.

## Age matching — 15 October 2026 feedback update

Age is now a casting constraint before profession preferences or avoiding
duplicate faces. Ordinary adult portraits stay within eight painted years of
characters under 30, and twelve years for older adults. Children and teenagers
retain their dedicated age pools. A young character reuses an age-suitable face
before receiving an unused older face. Where a human specialist bank has no
age-suitable artwork, casting uses an ordinary face of the right age instead.
Mutants and nonhuman bodies retain their matching artwork; limited banks use
the nearest available age rather than changing body type.

Saved faces are checked against `portraitAssignedAge`, not today's age, so an
appropriate identity survives birthdays and save/reload. Existing assignments
with clearly incompatible painted ages are corrected once and persisted. The
dossier now shows the actual character age alongside the portrait. Painted ages
are approximate art-direction bands, not exact likenesses at every age.

The full Flutter suite passed **571 tests** for this update, including age-cohort
sampling, exhausted-face pools, specialist fallback, saved-face repair and
unchanged gameplay RNG. The older counts and browser results below refer to
their original dated snapshots.

## Source and output

Original generated PNGs live in `assets/portraits-v2/source/batch_00.png` through
`batch_15.png`; the generation prompts are recorded in
`assets/portraits-v2/prompts.json`. All sixteen sheets were created with the
built-in `image_gen` tool; the prompt record identifies that tool and preserves
the complete per-batch instructions. Keep the originals at full resolution.

Run the packaging utility from the repository root:

```powershell
python scripts/portrait_library.py
```

Pillow is the only Python dependency. The utility validates all sixteen files
before writing runtime atlases to `upstream/assets/modern/portraits_v2/`.
Each source must be a square PNG at least 1024 pixels wide. Source boundaries
use shared rounded quarter coordinates, accommodating generated sizes such as
1254Ã—1254 without dropping or overlapping any source pixels. The source cells
can differ by one pixel in width or height. Each cell is individually downsampled to
256Ã—256 and placed into a 1024Ã—1024 runtime atlas, with no added padding.
Individual resizing prevents neighbouring cells from bleeding across boundaries.
There is no retouching or AI editing in this utility.

The last batch provides ten portraits; its last six cells remain in the atlas
but are absent from the catalog and must never be selected. Source files are
never changed by packaging. `manifest.json` is saved beside the source folder
and in the runtime folder. `assets/portraits-v2/overview.png` shows all 250
portraits, with identifying labels below each tile.

For a review while generation is still running:

```powershell
python scripts/portrait_library.py --partial
```

Partial mode writes only `overview-partial.png` and `validation-partial.json` in
the review folder. It never publishes an incomplete runtime catalog.

## Catalog conventions

Portraits use stable IDs `portrait_000` through `portrait_249`, in row-major
order. Every atlas has four columns, with presentation alternating female,
male, female, male. The rows correspond to approximate visual age bands
20â€“30, 30â€“45, 45â€“60 and 60â€“75. These labels are art direction and selection
metadata, not automated verification of the generated subjects.

| Batches | Profession group | Portraits |
| --- | --- | ---: |
| 00â€“02 | `professional` | 48 |
| 03â€“05 | `trades` | 48 |
| 06â€“07 | `academicMedical` | 32 |
| 08â€“10 | `streetCreative` | 48 |
| 11â€“12 | `securityMilitary` | 32 |
| 13â€“15 | `civilian` | 42 |
| Total | | 250 |

Each entry records `id`, `index`, `batch`, Flutter asset path, row, column,
profession group, presentation, age limits, runtime rectangle, original source
rectangle and an SHA-256 hash of the original RGB crop pixels. Atlas records
include source and runtime SHA-256 hashes and dimensions. Complete-sheet and
exact crop duplicates fail validation.

## Visual acceptance

Geometry and hashes cannot establish that an image generator followed every
instruction. Inspect the overview and original sheets before accepting artwork:

- Each cell must hold one centred individual without sheet borders, gutters,
  captions, watermarks or features crossing a cell boundary.
- Check the alternating presentation and row age direction, correcting metadata
  or replacing artwork if a generated cell differs materially.
- Check for near-duplicate faces, distorted anatomy, repetitive silhouettes and
  overly uniform clothing. Exact duplicate detection cannot catch these.
- Review both a larger face crop and a small squad-list thumbnail.

Do not change an existing portrait's identity or move its atlas position after
it has shipped. Saved portrait IDs rely on this mapping. Future additions should
use new IDs and atlas files.

## Verification on 15 October 2026

The completed library has sixteen source sheets and sixteen 1024Ã—1024 runtime
atlases. Both manifests agree and contain exactly 250 selectable portraits:
125 female presentations and 125 male presentations. Age-band counts are 64
(20â€“30), 64 (30â€“45), 62 (45â€“60), and 60 (60â€“75). Profession counts match the table
above. The final six generated cells are deliberately excluded.

An independent audit compared every manifest entry with the Dart catalog in
`upstream/lib/creature/portrait.dart`: portrait count, atlas grouping, row-major
coordinates, alternating presentation, and visual-age values all agree. Dart
uses numeric IDs 0â€“249 corresponding to manifest IDs `portrait_000`â€“`portrait_249`.
The renderer in `upstream/lib/modern/crew_portrait.dart` uses the same 4Ã—4 grid.
All source and runtime file SHA-256 hashes matched the manifest. All 250 source
crop hashes are distinct; no exact duplicate portrait crops were found.

The sixteen runtime PNGs total **30,084,775 bytes (28.691 MiB)**. Including the
runtime manifest, the directory totals **30,230,824 bytes**.

Visual review covered all 250 tiles in `assets/portraits-v2/overview.png` and
full-resolution representative sources 00, 04, 06, 08, 11, and 15, covering all
six profession groups. Portraits maintain consistent painted styling, clear face
framing, distinguishable hair silhouettes, and plausible approximate age
progression. Some generated sheets include a faint hairline at cell boundaries;
this does not cross the faces or prevent exact quarter-cell cropping. No
captions, watermarks, obvious facial malformations or blocking crop defects were
observed. Visual inspection is qualitative and does not prove that two fictional
faces cannot look related.

Code validation passed the complete Flutter suite: **501 tests**. Targeted Dart
analysis reported no issues. After the final loading-state adjustment, all 14
dossier widget tests passed again. Missing old-save identities are assigned
during migration, using shared identity maps rather than repeatedly scanning
the world for each character. Runtime assignment considers active crew,
recruitment/dating contacts and the current encounter.

The final compiled application also passed a focused Microsoft Edge browser
review at `http://127.0.0.1:8765/`, using a fresh isolated browser context and the
unchanged Felix save fixture. The review selected each of the five crew members,
verified successful page-origin atlas requests, and compared the central colour
of each rendered portrait with its saved ID's exact source atlas cell. Maximum
mean-channel colour difference was below 1.7/255. All five crew had distinct
saved portrait IDs, and exporting, loading and exporting again preserved every
crew identity. There were no page errors, console errors or failed requests.

Run the focused check with:

```powershell
node scripts/portrait_browser_review.mjs --url http://127.0.0.1:8765/ --out reports/portrait-browser-final
```

Evidence is in `reports/portrait-browser-final/report.json`, together with full
UI screenshots, individual portrait crops and portable save exports. Its
compiled `main.dart.js` SHA-256 is
`d654ade97ffd8089f774cf8be8028d9ba1963eb684c35007f0c12525d4b75327`, matching the
served build file. The complete Flutter log is `portrait-full-tests.log`.

## Specialist supplement

The specialist library adds 128 portraits, using IDs `portrait_250` through
`portrait_377`. The original 250 IDs, source sheets and manifest remain intact.
Supplemental runtime atlases are `batch_16.png` through `batch_23.png` in the
same `upstream/assets/modern/portraits_v2/` asset directory. This directory name
is retained so existing assets and saved identities continue to resolve.

| Batch | Art direction | Portraits |
| --- | --- | ---: |
| 16 | Punk, goth, emo and biker, one row each | 16 |
| 17 | Religious women/nuns and priests/pastors | 16 |
| 18 | Fictional human mutants | 16 |
| 19 | Children, approximate row ages 4, 7, 10, 12 | 16 |
| 20 | Teenagers/young adults, row ages 14, 16, 18, 19 | 16 |
| 21 | Dogs of varied breeds | 16 |
| 22 | Tanks and the game's unusual nonhuman body types | 16 |
| 23 | Elderly adults, approximate row ages 76, 84, 92, 100 | 16 |
| Supplement total | | 128 |
| Combined total | | 378 |

Batch 22 contains pairs of tanks, monsters, purple gorillas, warped bears,
pink elephants, mad cows and six-legged pigs, followed by one flaming rabbit
and one giant mosquito. Each image is fictional game artwork. Human batches
alternate female/male presentation by column. Dogs and other nonhuman subjects
have unspecified presentation in the art manifest; selection does not constrain
those subjects by gender. Approximate age metadata is art direction, not an
assertion that the generator's output determines a person's actual age.

Original supplemental images and complete generation prompts belong in
`assets/portraits-v3/source/` and `assets/portraits-v3/prompts.json`.
Package and validate the supplement with:

```powershell
python scripts/specialist_portrait_library.py
```

Use `--partial` to review available sources without publishing runtime files.
The utility writes `assets/portraits-v3/overview.png` with labels outside the
portraits, the supplemental `assets/portraits-v3/manifest.json`, and the runtime
`manifest-v3.json`. It never overwrites the original library's manifest. The
supplement uses the same geometric validation and per-cell resizing as the base
library. Duplicate source and exact crop hashes are checked against both
libraries. Human review remains required to assess anatomy, visual variety,
age direction and alignment; hashes cannot establish these properties.

The library remains finite. Campaign-specific selection and cosmetic variants
can reduce conspicuous repetition; they cannot guarantee an unlimited supply of
different faces. A saved identity should remain recognisable through gameplay.

### Appearance during a campaign

Human portraits preserve the painted face and add painted overlays for current
clothing at the collar/shoulders, supported head-covering armor and face masks.
A head wound receives a dressing while the head is wounded. Lost eyes and noses
receive corresponding dressings, using the body's anatomical left/right flags.
These marks follow current game state rather than becoming new source artwork.
Decades elapsed since a portrait was assigned add subtle forehead lines; the
renderer preserves existing hair and baldness. Cosmetic border palettes and corner marks provide another stable
variation when a painted face must be shared. They do not create new facial
anatomy or guarantee uniqueness. Nonhuman subjects skip human anatomy and
clothing overlays.

The dossier remains the authoritative account of medical status and equipment.
These compact visual cues cannot depict every garment or every possible injury.
Offline face-frame metadata helps position overlays; generated image geometry
still requires visual inspection at portrait and squad-thumbnail sizes. Source
artwork is not retouched by the overlay system.

The sixteen transparent painted overlay assets are recorded in
`assets/portraits-v3/refinement-prompts.json`; the untouched source sheet is
`assets/portraits-v3/source/appearance_overlays.png`. Packaging trims each cell
to its alpha>16 content bounding box (retaining RGBA pixels within the crop),
then resizes and packs it. The renderer samples the actual packed content
rectangle, avoiding a second transparent margin that would shrink the image.
Regenerate that geometry after repacking with
`python scripts/portrait_overlay_geometry.py`. A shaded geometric fallback is
available if the painted overlay asset fails to load.

Face-frame extraction found 345 of 346 human portrait faces, including the
specialist sheets. Portrait 295 omits facial overlays because its unusual mutant
face was not detected reliably. All 32 nonhuman portraits skip human facial
overlays. Unknown face coordinates are never guessed. The preview at
`reports/portrait-appearance-preview.png` covers healthy and injured faces,
clothing, helmets, masks, ageing and cosmetic variation.

After the specialist and painted overlay integration, all **534 Flutter tests**
passed, with no issues in scoped Dart analysis. Generated JSON serialization
was rebuilt successfully. The expanded tests cover all shipped profession
types, specialist pool exhaustion, age-appropriate casting, all body types,
read-only rendering, appearance persistence, dressing sides, baldness and
overlay geometry. A tank serialization discriminator defect discovered during
browser-fixture preparation was corrected and has a body/portrait round-trip
regression test. Logs are `reports/portrait-specialist-full-tests.log`,
`reports/portrait-specialist-analysis.log` and
`reports/portrait-specialist-serialization.log`.

The final web release compiled successfully and passed the specialist browser
review at `http://127.0.0.1:8765/`. Fifteen specialist characters across three
rosters were checked through ordinary UI save imports: subcultures, clergy,
mutants, a child, a teenager, dogs, a tank, other creatures and elderly adults.
The checks verified appropriate catalog IDs, successful atlas loading, source
face pixels, stable saved appearance fields and identical portraits after
save/reload. Seven appearance states covered baseline, left/right eye loss,
head/nose wounds, medical clothing, armor and ageing on a fixed face. Painted
overlays loaded successfully. The ageing check detected 120 changed forehead
pixels and no changes elsewhere; this is a subtle cue, not a full facial-age
transformation. There were no page errors, console errors or failed requests.

Run the browser check with:

```powershell
node scripts/portrait_specialist_browser_review.mjs --url http://127.0.0.1:8765/ --out reports/portrait-specialist-browser-final
```

The report and 25 screenshots are in
`reports/portrait-specialist-browser-final/`. The served and locally built
`main.dart.js` SHA-256 is
`4f85c81b57149f1f6e8020ba8e12ea463e5397e5b09334725f00823952561887`.
The offline manifest includes all 27 portrait runtime files (24 portrait
atlases, two metadata files and the appearance atlas), and its main-JavaScript
CRC matches the built file. This confirms asset inclusion and manifest
consistency; a full server-stopped offline playthrough was not repeated for
this portrait update.
