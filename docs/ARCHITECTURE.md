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

Profile selection follows the source reader's declared roster and current arrow actions, retaining its page and scroll. Renames, confirmations and event readers block person navigation. Footer and keyboard navigation update the journal selection. Equipment selection is presentation-only: highlighting a person must never dispatch the numbered action that removes their weapon. The active squad remains the original engine's squad.

Travel labels show costs and unmet requirements for the particular route. Free nearby destinations need no general travel warning. Full rules remain available through Order mechanics; displayed notes never override the source planner's action availability or departure checks.

Portraits use a separate deterministic identity calculation. Casting and rendering must not consume the gameplay RNG. Faces, assignment age and cosmetic variants persist in saves; appearance overlays reflect supported equipment and injuries. See [portrait details](PORTRAIT_LIBRARY.md).

Field movement, escape directions, speaker and conversation choices belong to their individual source readers. The source publishes the same availability used by its handler, including ordinary movement past frightened occupants. Retrying a prompt republishes its own actions; it never restores actions from an earlier reader. Field callbacks retain the action object and console revision. Read-only field dossiers keep the map in place and block both pointer and keyboard commands beneath them.

Hospital admission, discharge and court defense publish `RecoveryContext` snapshots in `engine/recovery_context.dart`. The journal reuses those people, text, costs, skill values and exact action objects; healing, billing, custody and verdicts remain in their original handlers. Full charges and medical mechanics are available on demand. Discharged patients return to their base without automatically rejoining a squad, and leaving a bill unpaid retains the debt.

## Development

Use a full restart after engine changes; hot reload cannot reliably restart an awaited game loop. Add meaningful regressions under `upstream/test/` when changing rules, persistence or command routing. Build and release tools live in `scripts/`; generated reports, SDKs and packages are ignored.

See [building](BUILDING.md), [testing](TESTING.md), [assets](ASSETS.md) and [changes](ORIGINAL_CODE_CHANGES.md).
