# Painted portrait library

The second portrait library contains 250 painted portraits in sixteen 4×4 atlases.
Image generation supplies complete painted portraits. The game selects a saved
portrait identity using broad profession, presentation and age pools. Skills do
not determine facial anatomy.

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
1254×1254 without dropping or overlapping any source pixels. The source cells
can differ by one pixel in width or height. Each cell is individually downsampled to
256×256 and placed into a 1024×1024 runtime atlas, with no added padding.
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
20–30, 30–45, 45–60 and 60–75. These labels are art direction and selection
metadata, not automated verification of the generated subjects.

| Batches | Profession group | Portraits |
| --- | --- | ---: |
| 00–02 | `professional` | 48 |
| 03–05 | `trades` | 48 |
| 06–07 | `academicMedical` | 32 |
| 08–10 | `streetCreative` | 48 |
| 11–12 | `securityMilitary` | 32 |
| 13–15 | `civilian` | 42 |
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

The completed library has sixteen source sheets and sixteen 1024×1024 runtime
atlases. Both manifests agree and contain exactly 250 selectable portraits:
125 female presentations and 125 male presentations. Age-band counts are 64
(20–30), 64 (30–45), 62 (45–60), and 60 (60–75). Profession counts match the table
above. The final six generated cells are deliberately excluded.

An independent audit compared every manifest entry with the Dart catalog in
`upstream/lib/creature/portrait.dart`: portrait count, atlas grouping, row-major
coordinates, alternating presentation, and visual-age values all agree. Dart
uses numeric IDs 0–249 corresponding to manifest IDs `portrait_000`–`portrait_249`.
The renderer in `upstream/lib/modern/crew_portrait.dart` uses the same 4×4 grid.
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
