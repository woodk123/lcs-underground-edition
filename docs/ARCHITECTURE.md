# Architecture

The Flutter project is in `upstream/`. Its layout stays close to [New Age](https://github.com/ashley-s-fox/lcs-new-age) so engine changes can be compared with the original project. This is a fork of the Dart game, with a new presentation layer.

## Engine and interface

- `upstream/lib/main.dart` starts the original sequential game loop.
- `upstream/lib/engine/` supplies the console, awaited input and structured screen/action metadata.
- `upstream/lib/modern/` contains the journal, dossiers, maps, creation screens and read-only help/calculation views.
- `upstream/lib/basemode/`, `daily/`, `monthly/`, `sitemode/`, `talk/` and `justice/` contain gameplay handlers.
- `upstream/lib/creature/` owns character data, skills, bodies and saved portrait identities.
- `upstream/lib/saveload/` handles persistence, migration, validation and import recovery.

The engine owns campaign state and action availability. UI controls dispatch the current source-authored action and revision through the controllers; labels, painted locations and pixel positions are not command identities. Inspectors and explanations read state without advancing the input loop or making gameplay rolls.

Orders use a local draft before confirmation. Changing actor discards that draft while retaining the order group, category and map browsing state. Ordinary confirmations keep the same category open for repeated assignments; required follow-up choices stay with their original reader. Confirming must affect the selected actor or squad only. Preserve the original timing, cost and eligibility checks in the gameplay handlers.

Travel labels show costs and unmet requirements for the particular route. Free nearby destinations need no general travel warning. Full rules remain available through Order mechanics; displayed notes never override the source planner's action availability or departure checks.

Portraits use a separate deterministic identity calculation. Casting and rendering must not consume the gameplay RNG. Faces, assignment age and cosmetic variants persist in saves; appearance overlays reflect supported equipment and injuries. See [portrait details](PORTRAIT_LIBRARY.md).

## Development

Use a full restart after engine changes; hot reload cannot reliably restart an awaited game loop. Add meaningful regressions under `upstream/test/` when changing rules, persistence or command routing. Build and release tools live in `scripts/`; generated reports, SDKs and packages are ignored.

See [building](BUILDING.md), [testing](TESTING.md), [assets](ASSETS.md) and [changes](ORIGINAL_CODE_CHANGES.md).
