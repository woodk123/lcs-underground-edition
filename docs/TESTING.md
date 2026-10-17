# Testing

Run commands from the repository root unless noted otherwise. Install the [pinned toolchain](BUILDING.md) and resolve dependencies/generate serializers using [Development mode](BUILDING.md#development-mode) first. A release build is not required for unit tests.

## Automated regressions

```powershell
Push-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub
..\.tools\flutter\bin\flutter.bat analyze --no-pub lib/modern lib/main.dart lib/engine/console.dart lib/engine/console_widget.dart lib/engine/console_char.dart lib/engine/console_graphic.dart
..\.tools\flutter\bin\flutter.bat analyze --no-pub --no-fatal-infos --no-fatal-warnings
Pop-Location
```

These analysis commands match the release/CI policy: focused interface analysis is strict; full-project errors fail while legacy warnings and infos remain visible.

The suite covers the original engine, command routing, order confirmation/cancellation, saves and migrations, equipment, politics, campaign endings, portraits and responsive UI. Save files under `upstream/test/saves/` are regression fixtures, not disposable player saves.

Release tooling uses Python's standard library:

```powershell
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/verify_assets.py
node --test scripts/browser_support.test.mjs
```

The tests exercise archive integrity/tampering, complete source snapshots, local and nightly packaging, release-size accounting and limits, unchanged-input detection and safe publication. Flutter regressions also decode every runtime WebP, check atlas dimensions and native alpha fidelity, and exercise conservative web renderer pruning. No live GitHub release is modified by these tests.

`test_serve.py` exercises real loopback HTTP responses and cold asset connection bursts. The accept queue is deliberately held while 48 clients connect, then every queued request must receive its expected response. MIME/security headers, launcher health, directory listing and path protection are also checked. The symlink case skips when Windows does not grant fixture creation privileges; no permission change is requested.

## Browser regressions

### Screen inventory and menu playthroughs

`screen_browser_review.mjs` supplements the longer gameplay journeys with title,
options, save management, every journal tab, roster/equipment/vehicle rails,
all five agenda pages, disband cancellation, archive pagination and full articles,
dossiers, sorting/reordering, order groups, guides and Classic view. It imports
a disposable copy of the bundled Felix campaign, clears wanted charges and
orders, and explicitly supplies a parked Jeep and twenty-five archive articles.
These prepared conditions are recorded in the report; they are not earned outcomes.

```powershell
$expected = (Get-FileHash (Join-Path $qaWeb 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/screen_browser_review.mjs --expected-hash $expected --out reports/screens-desktop
node scripts/screen_browser_review.mjs --expected-hash $expected --large --out reports/screens-large
```

`--large` uses 800×600 and 150% journal reading size. Each observed screen records
its controls, text and screenshot; failed routes remain in the report and fail
the command. The helper requires the same isolated port as the other browser checks.

`remaining_screens_playtest_test.dart` and
`orders_social_screens_playtest_test.dart` additionally render real source handlers
through `MainApp` at desktop and 800×600/150%. They exercise safehouse upgrades,
flags, promotions, all seven roster categories, sleeper orders, shops, selective
pawning and quantities, vehicle purchase/sale and buyer selection, crafting,
practice/classes, dating and hostage release. These are rendered widget
playthroughs, distinct from browser journeys. Current game data does not enable
mask sales; the empty legacy selector is checked for safe cancellation only.
The same suites cover all sorting variants, base-destination paging, special
publications, room rental/cancellation and live flag animations. Ending agenda
pages and completed high scores use isolated in-memory save storage.

`field_special_screens_playtest_test.dart` visits the original field-special
handlers, including lockups, prison controls, machinery, safes, laboratories,
studios, bank/vault, signs, security, the Oval Office and CCS rooms, plus prison
rehabilitation/labor/routine reports. Its geometry is an explicitly prepared
flat map with original squad skills. It chooses refusal/report paths; this is
screen coverage, not a claim to complete every heist, conversation or outcome.
Set `LCS_CAPTURE_SCREENS=1` for these three playtest files to save intermediate
rendered frames under ignored `reports/*-captures/` directories. Widget captures
and real-browser screenshots remain distinct evidence.

The supported browser helpers use isolated contexts and test fixtures. They require a compiled web build served at `http://127.0.0.1:18879/` and never operate a player's browser profile. Install Node.js/npm and the Edge/Chrome browser required by each helper. Their locked Node dependencies are in `upstream/tool/offline_test/`:

```powershell
npm ci --prefix upstream/tool/offline_test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch.ps1 -Port 18879 -NoBrowser
node scripts/browser_review.mjs --url http://127.0.0.1:18879/
```

`browser_review.mjs` checks dossier skill hierarchy, portrait-age repair, mechanics disclosure, retained order categories, repeated assignments, contextual travel labels, Clipboard dossiers and equipment pages at normal and enlarged text. Export comparisons verify that inspections/cancelled drafts preserve the campaign and repeated confirmations change only the intended members' assignments. Screenshots and JSON results are written under ignored `reports/`.

The first-week journey uses a separate synthetic campaign with old wanted crimes cleared and one explicitly ready prospect. It exercises the join decision, squad formation, weapon transfer, assignments, a real free shop visit, seven day advances, earned money/Science training and exact export/reimport continuity in a fresh browser context. It does not claim to earn the prospect's persuasion or manually certify native Windows gameplay.

```powershell
$expected = (Get-FileHash upstream/build/web/main.dart.js -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/first_week_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

Use the compiled `main.dart.js` hash from the extracted release player when checking that player. Both helpers keep browser profiles isolated from player saves.

Founder creation uses an installed Chrome and an exact compiled-build hash:

```powershell
$expected = (Get-FileHash upstream/build/web/main.dart.js -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/creation_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1 -Port 18879
```

The first helper uses installed Microsoft Edge. The creation helper checks portrait rerolls, continuity through creation/headquarters/save reload, projected answer-bonus help and click-through, and public-name placement below the question. It covers manual and random backgrounds at normal size and 800×600 with 150% text. Unit regressions cover all 50 source bonuses, untouched state/RNG/ID counters during previews, and the birthday/cohort edge case. Use only the isolated QA port when stopping a test server.

### Mission, recovery and custody

When a player server is already running, build the QA game into a separate ignored directory. Pass an **absolute** `--output` path to the pinned Flutter `build web --release --no-pub --no-wasm-dry-run --base-href /` command, then run `tool/inject_service_worker.dart` against that directory exactly once. Relative custom output paths can fail Windows shader compilation. Use `scripts/common.ps1` / `Get-LcsFlutter` to verify the pinned SDK before building. Do not replace files served to the player on port 8765.

```powershell
$qaWeb = Join-Path (Get-Location) 'reports/mission-qa/web'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch.ps1 -Port 18879 -NoBrowser -WebRoot $qaWeb
$expected = (Get-FileHash (Join-Path $qaWeb 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/mission_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

The mission helper travels into an actual police building, moves through its entrance, waits for an encounter, inspects a field dossier, exercises escape-direction retry/cancellation, fights and retreats using current UI controls. Exports verify ammunition consumption and headquarters return. Any wounds actually sustained are taken to the university hospital and advanced through treatment until discharge or a recorded siege interruption. Separate prepared campaigns exercise unarmed political conversation, paid/unpaid hospital care with bleeding, and a month-end custody transition through police transfer, trial and prison release. The report declares all prepared conditions, including wounds, funds, custody status and dates; prepared arrests or persuasion are never described as earned through play.

If an earned police siege blocks day advancement during actual-injury care, the helper records the siege and still-admitted patients explicitly and preserves that campaign snapshot. It does not claim discharge or resolve the siege by altering state. The separate prepared care scenarios continue to check discharge; siege resolution is outside this helper's coverage.

Each resolved scenario saves and exports through the original menu, reloads the browser, and imports into a fresh storage context. Whole-campaign equality covers character condition, portrait identities, equipment/ammunition, squads, orders, funds and campaign progress. Hospital/court pages are also exercised at 800×600 with 150% reading size. Screenshots, decision frames, synthetic inputs and exported saves remain under ignored `reports/`. `--only operation|conversation|paid-care|unpaid-care|custody` helps investigate one scenario; the full acceptance run omits this filter.

The helpers locate installed Edge/Chrome in standard Windows directories and accept `--browser-executable <path>` for another installation. They never download a browser, reuse a player profile or clear player storage. Field-input regressions cover retries, source identity/revision checks, the original movement exception and keyboard isolation while inspecting. Recovery regressions cover billing, affordability, conviction records, exact persistence, responsive journal routes and read-only details. These checks do not certify every injury, pursuit, siege, trial outcome or native Windows path.

### Street arrest and Free Clinic

```powershell
$expected = (Get-FileHash (Join-Path $qaWeb 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/street_clinic_browser_review.mjs --expected-hash $expected
```

This helper closes the earlier street-arrest and Free Clinic coverage gaps. It starts a healthy campaign copy with no wanted charges, removes a non-founder's clothing through the actual equipment controls, assigns donation collection, and advances the original daily checks until police accost the member. The normal indecency check and gameplay RNG remain unchanged. The browser inspects the pursuit dossier, retries an invalid key and surrenders through the current source action at 800×600/150% text. State observations verify the new charge, interrupted income, police custody, confiscated weapon/ammunition, cleared order, original squad cleanup and founder remaining at headquarters. The arrest is produced during play rather than inserted into a fixture.

A separate declared wounded campaign visits the actual Free Clinic, admits its patient and advances treatment through discharge. The browser verifies that care persists on subsequent days, restores blood, charges no new fee and retains equipment/portrait identity. Exports are used to observe the resulting engine state; this helper does not add a save-transfer journey. `--only street|clinic` runs one path. `--baseline` records known defects on an older compiled build for comparison; normal acceptance omits it.

The corresponding Flutter regressions run the original donation, admission, daily recovery, task and squad readers. They cover pursuit input isolation, modal inspection, clinic patients versus sleeper workplace staff, the existing 60-day discharge limit, pre-existing medical debt, and unchanged university healing/billing. Every possible injury and every alternate court outcome remain separate coverage concerns.

### Car pursuits

```powershell
node scripts/car_chase_browser_review.mjs --expected-hash $expected
```

The car helper imports a declared isolated campaign containing the original Teachlocks character from the bundled EQ fixture, with unchanged attributes and skills, plus a loaded rifle and spare ammunition for the combat scenario. Headquarters, squad membership, idle orders and cleared wanted charges are prepared conditions. The browser assigns car theft, finds a vehicle, breaks its window and starts it through the original activity. Ordinary gameplay rolls determine whether theft leads to a car pursuit; successful thefts without a chase and police interruptions on foot are recorded separately. Chase entry and outcomes are never inserted into the fixture or forced by changing RNG.

Separate fresh contexts exercise driving escape, opening fire and resolving the encounter, pulling over into police custody, abandoning the car for an on-foot pursuit, and repeatedly fighting through an actual terminal outcome. Fight-to-end never voluntarily drives away, bails out or surrenders; source-forced on-foot transitions and defeat/death are recorded honestly. Removed unrecovered bodies, retained bodies at their base and the engine's `-1` on-foot car sentinel are recognized explicitly. Retained corpses keep their original equipment and historical orders; their death, lost vehicle and cleared squad membership are verified. Current source controls are used throughout, including contextual obstacle choices. Reports include decision frames, chosen actions, actual outcomes, screenshots, ammunition observations and post-operation state exported through the save menu. Dossiers and enlarged reading size are checked during a live car reader. `--only escape|fight|surrender|bailout|fight-to-end` selects one scenario; `--only remaining` runs bailout and terminal combat. `--baseline` is for evidence against an older compiled build. Generated evidence stays under ignored `reports/`.

`car_chase_engine_test.dart` and `car_pursuit_journal_test.dart` cover the original escape/combat/capture handlers, convoy confiscation versus parked vehicles, obstacle controls, retry and nested-reader isolation, responsive journal actions and read-only dossiers. Animation regressions check stable RNG/revisions, clean reports, positive scheduling, left-edge overlaps, replacement consoles and cleanup on failure. `post_operation_recovery_test.dart` checks the original full daily handler and enlarged journal Continue control when a severe injury requires treatment after a field reader. Engine fixtures declare stronger skills where needed to make handler outcomes deterministic; these setup values are not gameplay balance changes or browser-play claims. These checks do not cover every vehicle, obstacle outcome, pursuit strength or native Windows path.

### Headquarters sieges

```powershell
node scripts/siege_browser_review.mjs --expected-hash $expected
```

The siege helper declares prepared police encirclement/attack conditions, headquarters ownership, local inventory/vehicles, standard equipment and a local roster combining original bundled characters without changing their attributes or skills. A bleeding hospital patient and a separate bleeding squad with its own vehicle remain outside the response. The browser exercises surrender, an exterior breakout, camp defense and a tactical warehouse evacuation drill. The drill explicitly prepares open-floor geometry while retaining the original enemy generation, traps, movement and exit handlers; it does not certify normal-map navigation. No outcome or gameplay RNG is supplied.

Each response uses the current source controls, including the exact victory acknowledgement and enlarged headquarters responses. State observations verify custody/deaths, injuries, ammunition and equipment, stored supplies, driven versus parked vehicles, ownership, escalation and hiding. Hospital/off-site people and their squad/vehicle are compared before any subsequent day advances. Continued recovery checks return hiding survivors and discharge patients to the existing valid-base fallback after a rented headquarters is lost. Actual battle injuries admitted to hospital are followed through care too; a new siege that blocks further time is explicitly recorded with any still-admitted survivors. `--only surrender|escape|defense|assault-escape` selects one case. `--baseline` records missing controls and blocked report readers against older compiled builds.

The `siege_journal_test.dart`, `siege_campaign_consequences_test.dart` and `car_remaining_paths_test.dart` suites exercise the original handlers and source actions. They cover local versus remote squad selection, exact displayed targets, immutable details, stale/nested callbacks, dossier keyboard isolation, source police reports, bailout, terminal combat/death persistence, hauled/reserve participants, outside-patient bleeding and prison-escape flags, vehicle/ownership consequences, and discharge after headquarters loss. Prepared first-reader tests are distinct from full outcome tests.

Run the browser helpers sequentially for a complete acceptance pass, keeping fresh-context startup loads separate. Preserve failed/interrupted reports as well as successful final reports. These paths do not certify every siege faction, escalation, generated map or campaign ending; native Windows GUI checks remain separate.

## Release checks

Each build report records automated command exit codes and source identity. Generated reports and old test counts are not a substitute for a current run. Review the build log and release-specific metadata for what actually ran.

```powershell
python scripts/verify_package.py 'release/<build>/<extracted-package-folder>'
```

Keep its ZIP and `.zip.sha256` beside the extracted folder. Verification checks the manifest, file inventory, paths, archive SHA-256 and each ZIP member's contents/CRC.

Before describing a release as manually accepted, test its extracted launcher, campaign creation, load/save/export/import, assignments, day advancement and any changed gameplay path. Browser offline claims need cache activation plus a save/reload with networking disabled; server-stopped claims need the test server actually stopped. Native GUI and clean-machine launch checks are separate from compilation and browser results.

Historical reports are retained in Git history, old release artifacts and local ignored evidence. Published previews keep their original verification scope; later source or packaging changes do not retroactively certify them.
