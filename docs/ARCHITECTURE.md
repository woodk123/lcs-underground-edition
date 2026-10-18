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

The Network tab wraps the original sleeper order readers with a permanent roster, current-role inspector and explicit draft confirmation. The source shares its exact assignment-eligibility reason with this view; unavailable living sleepers remain visible. Monthly standing orders and next-eligible-day recall keep their original processing. Role-review acknowledgements live in local preferences keyed by campaign and person, separate from exported saves. Job, workplace, order or availability changes invite review; ordinary date, infiltration and recovery-countdown changes do not. Keeping a current role is presentation-only.

Profile selection follows the source reader's declared roster and current arrow actions, retaining its page and scroll. Renames, confirmations and event readers block person navigation. Footer and keyboard navigation update the journal selection. Equipment selection is presentation-only: highlighting a person must never dispatch the numbered action that removes their weapon. The active squad remains the original engine's squad.

Travel labels show costs and unmet requirements for the particular route. Free nearby destinations need no general travel warning. Full rules remain available through Order mechanics; displayed notes never override the source planner's action availability or departure checks.

Portraits use a separate deterministic identity calculation. Casting and rendering must not consume the gameplay RNG. Faces, assignment age and cosmetic variants persist in saves; appearance overlays reflect supported equipment and injuries. See [portrait details](PORTRAIT_LIBRARY.md).

Field movement, escape directions, speaker and conversation choices belong to their individual source readers. The source publishes the same availability used by its handler, including ordinary movement past frightened occupants. Retrying a prompt republishes its own actions; it never restores actions from an earlier reader. Field callbacks retain the action object and console revision. Read-only field dossiers keep the map in place and block both pointer and keyboard commands beneath them.

Hospital admission, discharge and court defense publish `RecoveryContext` snapshots in `engine/recovery_context.dart`. The journal reuses those people, text, costs, skill values and exact action objects; healing, billing, custody and verdicts remain in their original handlers. Full charges and medical mechanics are available on demand. Discharged patients return to their base without automatically rejoining a squad, and leaving a bill unpaid retains the debt.

Daily professional-treatment warnings clear the departing reader before authoring their notice. A field screen's body boundary must not hide the warning or leave the engine waiting without a current Continue action.

On-foot and car pursuits publish `PursuitContext` snapshots in `engine/pursuit_context.dart`. They expose only crew, road conditions, vehicle gaps and encounter information already printed by the current source reader. The pursuit journal retains action identity/revision checks across retries and nested status/equipment readers; its dossier is a read-only modal. Obstacle controls retain their current source meanings, including F for slowing down. Street arrests still come from the original daily activity checks and surrender handler.

Car road animation is cosmetic. It repaints its captured console only while the car reader awaits input, without consuming campaign RNG, changing command revisions or contributing glyphs to authored reports. Nested readers own the console while open. The chase stops and awaits animation cleanup on every exit; driving, combat, obstacles and capture remain in the original handlers.

Siege responses stay in the headquarters journal with the squad leader rail on the left. The original headquarters reader publishes an immutable `SiegeBriefing` and its exact F/G/W capabilities in `HeadquartersFrame`. The journal shows the current attack, consequences and responses; supply/security detail expands on demand. Responses retain their source action and revision, and inspection blocks battle/surrender keys. The source passes the displayed site into its response initializer and forms defense from people physically there, preserving other squads and hospital patients.

Operation cleanup snapshots participants before custody, hauling or relocation changes their membership. Stabilization and prison-escape flag cleanup apply to that roster, including hauled people and local siege reserves. People at other sites keep their condition. Defeated solo pursuits, uncarried casualties, reserve promotion and fatal car crashes clear dead actors' reverse squad membership when removing them. Living hauled people retain their in-operation ownership. Police siege confiscation reports use one authored acknowledgement reader so Continue remains available.

Free Clinic patients remain admitted until the existing healed/60-day discharge condition. Clinic support remains 6 at an ordinary non-LCS site and generates no new treatment bill; university hospitals retain support 16 and law-dependent charges. Sleeper staff at their own clinic workplace are distinguished from admitted patients.

## Development

Use a full restart after engine changes; hot reload cannot reliably restart an awaited game loop. Add meaningful regressions under `upstream/test/` when changing rules, persistence or command routing. Build and release tools live in `scripts/`; generated reports, SDKs and packages are ignored.

See [building](BUILDING.md), [testing](TESTING.md), [assets](ASSETS.md) and [changes](ORIGINAL_CODE_CHANGES.md).
