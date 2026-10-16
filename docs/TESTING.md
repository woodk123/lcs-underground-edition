# Testing

Run commands from the repository root unless noted otherwise. Install the [pinned toolchain](BUILDING.md) and generate dependencies/serialization with the build script first.

## Automated regressions

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub
..\.tools\flutter\bin\flutter.bat analyze --no-pub
```

The suite covers the original engine, command routing, order confirmation/cancellation, saves and migrations, equipment, politics, campaign endings, portraits and responsive UI. Save files under `upstream/test/saves/` are regression fixtures, not disposable player saves.

Release tooling uses Python's standard library:

```powershell
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/verify_assets.py
node --test scripts/browser_support.test.mjs
```

The tests exercise archive integrity/tampering, complete source snapshots, local and nightly packaging, release-size accounting and limits, unchanged-input detection and safe publication. Flutter regressions also decode every runtime WebP, check atlas dimensions and native alpha fidelity, and exercise conservative web renderer pruning. No live GitHub release is modified by these tests.

## Browser regressions

The supported browser helpers use isolated contexts and test fixtures. They require `http://127.0.0.1:18879/` and never operate a player's browser profile. Their Node dependencies are in `upstream/tool/offline_test/`:

```powershell
npm install --prefix upstream/tool/offline_test
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

Separate fresh contexts exercise driving escape, opening fire and resolving the encounter, and pulling over into police custody. Current source controls are used throughout, including contextual obstacle choices. Reports include decision frames, actual outcomes, screenshots, ammunition observations and post-operation state exported through the save menu. Dossiers and enlarged reading size are checked during a live car reader. `--only escape|fight|surrender` selects one scenario; `--baseline` is for evidence against an older compiled build. Generated evidence stays under ignored `reports/`.

`car_chase_engine_test.dart` and `car_pursuit_journal_test.dart` cover the original escape/combat/capture handlers, convoy confiscation versus parked vehicles, obstacle controls, retry and nested-reader isolation, responsive journal actions and read-only dossiers. Animation regressions check stable RNG/revisions, clean reports, positive scheduling, left-edge overlaps, replacement consoles and cleanup on failure. `post_operation_recovery_test.dart` checks the original full daily handler and enlarged journal Continue control when a severe injury requires treatment after a field reader. Engine fixtures declare stronger skills where needed to make handler outcomes deterministic; these setup values are not gameplay balance changes or browser-play claims. These checks do not cover every vehicle, obstacle outcome, pursuit strength or native Windows path.

## Release checks

Each build report records automated command exit codes and source identity. Generated reports and old test counts are not a substitute for a current run. Review the build log and release-specific metadata for what actually ran.

```powershell
python scripts/verify_package.py 'release/<build>/<extracted-package-folder>'
```

Keep its ZIP and `.zip.sha256` beside the extracted folder. Verification checks the manifest, file inventory, paths, archive SHA-256 and each ZIP member's contents/CRC.

Before describing a release as manually accepted, test its extracted launcher, campaign creation, load/save/export/import, assignments, day advancement and any changed gameplay path. Browser offline claims need cache activation plus a save/reload with networking disabled; server-stopped claims need the test server actually stopped. Native GUI and clean-machine launch checks are separate from compilation and browser results.

Historical reports are retained in Git history, old release artifacts and local ignored evidence. Published previews keep their original verification scope; later source or packaging changes do not retroactively certify them.
