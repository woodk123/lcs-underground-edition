# Testing

Run commands from the repository root unless noted otherwise. For Flutter checks, install the [pinned toolchain](BUILDING.md) and resolve dependencies/generate serializers using [Development mode](BUILDING.md#development-mode) first. A release build is not required for unit tests. Documentation checks below need only Python.

Start with [focused checks](#choose-focused-checks) while iterating, then [shared acceptance](#shared-acceptance-journey) when the common player journey is affected. [Isolated browser setup](#prepare-an-isolated-web-build) prepares one build for the supplemental graphical journeys below; [release checks](#release-checks) cover extracted packages and manual acceptance.

## Documentation and skill checks

```powershell
python scripts/verify_docs.py
```

This local-only check covers root `AGENTS.md`/`README.md`, Markdown under `docs/`, and repository skills under `.agents/skills/`. It checks relative file, directory and image targets, exact path case, Markdown heading anchors and common reference links. Code examples are excluded from link checks, and external destinations are skipped without network requests. It supports this repository's Markdown conventions; it does not render Markdown or validate commands and external pages.

Add `--powershell` on Windows to parse fenced PowerShell examples without executing them. Requested parsing fails explicitly if its parser is unavailable; default link checks need no PowerShell. Use `--json` for structured diagnostics or `--root <checkout>` to inspect another checkout. When changing the verifier, run `python -m unittest discover -s scripts -p test_verify_docs.py -v`.

Ordinary Python test discovery also checks the maintained links in its own checkout or extracted Source ZIP. Live PowerShell parsing remains opt-in.

## Supported window sizes

The minimum supported game area is **1024×720 logical pixels**; the Windows startup default remains **1280×720**. Browser dimensions refer to the usable page viewport, excluding browser chrome. Use 1024×720 with 150% reading size for compact acceptance checks, alongside the normal desktop case. Keep controls reachable through scrolling and keyboard focus when enlarged text needs more space.

Smaller windows, including 800×600 and phone-sized viewports, are outside the supported layout target. Existing narrower component tests are optional overflow and robustness checks, not additional supported resolutions. They must not dictate the normal desktop layout. Historical captures and reports retain the dimensions at which they were recorded; rerun current helpers for evidence against the new minimum.

## Automated regressions

For exploratory gameplay and stuck-reader investigation, use the [development MCP](DEV_MCP.md). It records the actual loaded build and source-action trace in disposable storage. Turn discovered defects into the focused regressions and browser journeys below; structured engine actions do not certify graphical interaction.

### Choose focused checks

Start with the row matching the changed boundary; combine rows when a change crosses boundaries. These are existing regressions, not substitutes for the integrated journeys. Dart file names below are relative to `upstream/test/`; tooling paths are relative to the repository root.

| Changed area | Focused test files | Integrated verification |
|---|---|---|
| Organisation footer, HQ commands or draft guards | `organisation_journal_test.dart`, `organisation_discovery_test.dart`, `network_journal_test.dart` | Shared acceptance: ordinary orders, required Continue, cancellation, HQ routing and keyboard interface. |
| Orders browsing, search, retained category/map or scroll | `organisation_journal_test.dart`, `keyboard_orders_workspace_test.dart`, `page_storage_isolation_test.dart` | Shared acceptance: search across categories, switch actor, confirm/cancel, help, map toggle and revisit at normal/enlarged reading size. |
| Shell navigation, shared controls, focus or reading preferences | `journal_navigation_state_test.dart`, `organisation_journal_test.dart`, `section_navigation_test.dart`, `keyboard_navigation_test.dart`, `text_prompt_focus_test.dart`, `journal_preferences_test.dart`, `journal_title_test.dart` | Shared acceptance, plus the screen browser review for shell routes outside its coverage. Check Classic switching and retained controls. |
| Input ownership, keyboard routing or bridge blockers | `game_input_policy_test.dart`, `text_prompt_focus_test.dart`, `keyboard_navigation_test.dart`, `keyboard_orders_workspace_test.dart`, `classic_keyboard_parity_test.dart`, `development_bridge_test.dart` | Follow the [input ownership priorities](INPUT_OWNERSHIP.md), run the [bridge suite enabled as well as default-disabled](DEV_MCP.md#verification), then shared acceptance and affected modal/keyboard browser journeys. |
| Source action dispatch or order preparation/commit | `action_identity_test.dart`, `organisation_controller_test.dart`, `organisation_visit_test.dart`, `classic_keyboard_parity_test.dart` | Shared acceptance, plus the affected actual source reader; check stale callbacks and required follow-up choices. |
| Visit coordination or workspace/profile layouts | `organisation_visit_flow_test.dart`, `organisation_journal_test.dart`, `organisation_visit_test.dart`, `journal_processing_test.dart`, `classic_keyboard_parity_test.dart`, `journal_screen_audit_test.dart` | Shared acceptance and the screen browser sweep at desktop/enlarged reading size. Check squad changes, prepare/cancel/revisit/queue, profile input, focus and retained scrolling. |
| Save/version handling | `game_version_test.dart`, `save_load_test.dart`, `save_round_trip_test.dart`, `save_recovery_test.dart`, `journal_title_test.dart` | Shared acceptance save transfers and the [version policy](VERSIONING.md#save-compatibility). |
| Field map/report layout or tactical reader controls | `field_prompt_test.dart`, `mission_input_test.dart`, `tactical_shell_acceptance_test.dart`, `tactical_actions_flow_test.dart` | Mission browser tactical/conversation journeys: retained map bounds, decisions/text, dossier dismissal, source actions and compact/enlarged layout. |
| Acceptance runner or browser support | `scripts/test_shared_acceptance.py`, `scripts/browser_support.test.mjs` | Run the shared acceptance entry point against one identified build. |

For example, while changing Orders browsing, run the matching files with the pinned SDK:

```powershell
Push-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub test/organisation_journal_test.dart test/keyboard_orders_workspace_test.dart test/page_storage_isolation_test.dart
Pop-Location
```

Once source is settled, run `python scripts/shared_acceptance.py` for changes spanning creation, orders, navigation or saves. It retains the fresh founder's continuation and separate prepared scenarios. Follow the [browser regressions](#browser-regressions) instructions for supplemental helpers: use isolated origins and the same compiled JavaScript hash. Keep run evidence under ignored `.local/` or `reports/`; do not infer current coverage from old timings or counts.

### Analysis and broader checks

```powershell
$analysisTargets = python scripts/analysis_targets.py | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not load the strict analysis scope.' }
Push-Location upstream
try {
    ..\.tools\flutter\bin\flutter.bat test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    ..\.tools\flutter\bin\flutter.bat analyze --no-pub @analysisTargets
    if ($LASTEXITCODE -ne 0) { throw 'Focused analysis failed.' }
    ..\.tools\flutter\bin\flutter.bat analyze --no-pub --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE -ne 0) { throw 'Full-project analysis failed.' }
} finally {
    Pop-Location
}
```

The strict analysis paths are maintained in [scripts/analysis_targets.json](../scripts/analysis_targets.json), shared by this command, CI and the standalone Windows/Linux builders. Focused interface analysis is strict; full-project errors fail while legacy warnings and infos remain visible.

For changes to versioning, run the focused [version/save/title checks](VERSIONING.md#save-compatibility). These verify that the Underground package and displayed versions agree, autosaves retain their compatibility header, existing campaigns still load, and the longer footer fits at narrow/enlarged layouts.

The suite covers the original engine, command routing, order confirmation/cancellation, saves and migrations, equipment, politics, campaign endings, portraits and responsive UI. Save files under `upstream/test/saves/` are regression fixtures, not disposable player saves.

Organisation tests share campaign fixture and headquarters-reader helpers under `upstream/test/support/`. Keep each scenario's extra crew, orders and outcomes explicit in its test. Reader shutdown must retain the suite's own pumping: widget tests use fake time, while controller tests await real asynchronous completion.

The City maps journey switches squads, rejects a retained queue callback, prepares and cancels through the original planner, revisits the destination and queues only the intended squad at desktop and 1024×720/150%. Complete campaign and RNG comparisons cover browsing/cancellation and actor-only queuing. `organisation_visit_flow_test.dart` separately pauses a controlled reader to verify that squad changes, invalidation and disposal prevent late district commands; it supplies no gameplay outcome. Processing regressions retain pending input and campaign/RNG while waiting for the original next reader. These tests run through shared acceptance.

Order mechanics regressions exercise desktop and enlarged layouts through help dismissal, presentation rebuilds and cancellation, retaining the selected actor, draft, mechanics scroll, source revision and campaign/RNG state. They inspect restored game keyboard focus directly. Pursuit regressions cover live reading-size reflow and keyboard traversal into overflowing commands; the car browser review separately checks actual web accessibility bounds and the original surrender/custody/save journey.

Nested squad-choice regressions in `remaining_screens_playtest_test.dart` exercise actual equipment, reordering, kidnapping and hostage-release readers at desktop and 1024×720/150%. They check initially reachable controls, stale-command removal, second-stage cancellation, target-key validation, disabled empty-handed carriers and releasing only the selected hostage. These are declared prepared scenarios, separate from earned campaign play.

Fresh-campaign flow regressions include pending recruitment readiness compared with the original meeting menu, new recruit/custody/ended-visit follow-ups across restarts, live victory counts compared with `winCheck`, original rent exemptions and eviction timing, and draft guards for personal orders, Network, visits and Bases purchases. Retained callbacks are exercised after cancellation and replacement; read-only views preserve full campaign snapshots and gameplay RNG. The small-screen checks retain visible first-row actions and order timing at enlarged reading sizes.

Month-end regressions exercise actual sleeper handlers, coherent earnings/exposure and delivery reports, unsupported workplaces, blind-time completion and unchanged valid-operation RNG. Production tests compare daily writing/streaming with original influence accumulation and active publication staffing; source publication choices verify one-copy consumption and refusal retaining evidence. Ledger tests cover period labels, required acknowledgement before history capture, source-total reset, bounded local history across restarts/campaign changes/older saves, pagination, keyboard isolation and enlarged reading sizes. Prepared source scenarios are separate from genuinely earned browser playthrough results.

Release tooling uses Python's standard library, with pinned Pillow for the portrait packager's image-based approval tests. CI installs it on tooling shards; local checks use the same requirement:

```powershell
python -m pip install -r scripts/requirements-art.txt
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/verify_assets.py
npm ci --prefix upstream/tool/dev_mcp --no-audit --no-fund
npm test --prefix upstream/tool/dev_mcp
```

The Node command runs the development-MCP, shared browser-support and offline-cache contract tests without launching a browser. The cache regressions reject partial, stale-version and wrong-scope caches even when other caches contain many entries. For a focused browser-support change, use `node --test scripts/browser_support.test.mjs`. Browser journeys below have their own locked dependencies in `upstream/tool/offline_test/`.

The tests exercise archive integrity/tampering, complete source snapshots, local and nightly packaging, release-size accounting and limits, unchanged-input detection and safe publication. Flutter regressions also decode every runtime WebP, check atlas dimensions and native alpha fidelity, and exercise conservative web renderer pruning. No live GitHub release is modified by these tests.

`test_serve.py` exercises real loopback HTTP responses and cold asset connection bursts. The accept queue is deliberately held while 48 clients connect, then every queued request must receive its expected response. MIME/security headers, launcher health, directory listing and path protection are also checked. Content-validator regressions cover older archive timestamps, identical file sizes/timestamps, legacy date-only cache requests, weak/list ETags and HEAD responses. The symlink case skips when Windows does not grant fixture creation privileges; no permission change is requested.

Expected browser disconnects do not print server tracebacks when a page or disposable profile closes during an asset response. Unexpected handler/file errors retain their diagnostics; loopback regressions cover both cases and continued serving afterward.

Windows launcher regressions use disposable command/process fixtures to check compatible Python selection, actual argument quoting, canonical directory identity and refusal to stop an unrelated process. Their live child only prints arguments; process-stop calls are mocked. They preserve existing player and QA servers.

Journeys using the shared browser-page helper retain failed request methods, resource types, network error text and connection/request timing alongside scenario context. Keep this evidence when investigating a startup transport failure; a later successful request alone does not establish its cause.

## Shared acceptance journey

`player_guidance_test.dart` checks loaded/compatible spare ammunition, per-patient First Aid eligibility, unchanged campaign/RNG during readiness inspection, source stealth feedback without clearing alarm/suspicion, and operation cash/loot separation with history round-trip. Visit and recovery journeys cover the integrated readiness inspector, enlarged discharge/payment controls and rejoining guidance; pawn journeys verify itemized receipts against stock removed and funds received.

Run the common creation, opening-week, organisation and save journey from the repository root:

```powershell
python scripts/shared_acceptance.py
```

Browser journeys run with **four workers** by default. Creation must pass,
including its exported founder and exact loaded-build checks, before the fresh
opening week starts. Other journeys use independent browser profiles and output
directories against the same read-only web build. Use `--browser-workers 1` for
sequential troubleshooting or choose a limit from 1 to 5. Four is intended for a
machine with ample CPU and memory; lower it when running other heavy workloads.
The coordinator retains independent failures, marks dependent journeys blocked,
and waits for browser cleanup before releasing its servers. `browser_seconds`
records elapsed browser time; per-step durations overlap and must not be added
to calculate elapsed time. Step start/completion timestamps show the overlap.

Shared browser helpers wait for expected accessible reader text, portrait changes,
tooltip visibility and daily reader transitions. Scrolling, resizing and ignored
keyboard commands also wait for stable rendered semantics. These checks replace
fixed pauses; they do not skip the original actions, layout checks or save comparisons.

Install the pinned SDK and resolve dependencies as described in [Building](BUILDING.md#development-mode). The browser helpers use installed Chrome and Edge, with locked dependencies installed by `npm ci --prefix upstream/tool/offline_test`. The runner bootstraps and verifies the SDK before project dependency resolution or serializer generation, then runs the focused test files (including legal summaries and operation history), builds a separate release web player and injects its offline manifest. Supplied builds must pass their file/hash checks before SDK or server work and remain unchanged through the run. It then runs these existing helpers against that one build:

| Stage | What it establishes |
|---|---|
| Creation | Actual manual and fate creation, desktop/enlarged layouts, portrait continuity, and the manual founder's manifesto Juice and skill rewards in the exported save. |
| Fresh opening week | Imports that unchanged manual founder, confirms Science practice, advances seven actual days, checks accounting/training/identity, and transfers the complete result through a fresh browser profile. No people or rewards are supplied. |
| Prepared recruitment week | The existing Felix fixture with cleared wanted crimes and one explicitly ready prospect; real recruitment acceptance, squad formation, equipment transfer, orders, a local visit, seven days and exact save transfer. This does not claim to earn the prospect's persuasion. |
| Organisation | Existing dossier, draft/cancel, repeated assignment, travel, equipment and personnel journeys, including enlarged layouts and mechanics-dialog keyboard isolation. |
| Keyboard interface | The unmodified Felix fixture, the identical original keyboard assignment sequence in Classic and graphical desktop/compact 1024×720/150%, with immediate task choices and original Back behaviour, exact actor-only campaign changes, modal isolation and persistent display preferences. Fixture import/export and preference changes are setup outside the measured task sequences. |
| Personnel | Existing declared mixed-status fixture, including a hospitalized person; finding absent crew, retained search/category, dossiers and complete campaign preservation. |

The focused tests cover source creation/rewards, order routing and retained scroll/selection, page-storage isolation, current Network orders and modal shortcuts, personnel, and save load/round-trip/recovery. This is the shared integration check; the full suite, rare gameplay branches, offline acceptance and native GUI checks retain their separate scopes below.

Keyboard interface regressions add `keyboard_orders_workspace_test.dart`, `keyboard_reader_choices_test.dart`, `character_presentation_test.dart` and `journal_preferences_test.dart`. They exercise real assignment, equipment and buyer readers, stale callbacks, exact case-sensitive vehicle shortcuts, compact/enlarged/narrow layouts, consistent attribute order, accessible details, pending text/input, unchanged campaign/RNG during inspection and preference persistence independently of reading size. `keyboard_interface_browser_review.mjs` records actual task key sequences, screenshots and whole-campaign exports; its comparison requires the identical original key sequence and immediate assignment timing in both views, with separate pointer draft/cancel/confirm coverage.

On failure, the keyboard helper freezes pending page and service-worker requests before closing the profile, alongside resource timings, worker state and the raw development reader when available. A mounted processing shell or an empty failed-request list does not establish completed startup; inspect the retained loading stage and pending requests before retrying.

The runner reserves **18879 and 18882** by default and fails if either is occupied, with exclusive socket ownership on Windows. For concurrent runs, choose two different unused dedicated ports with `--port 18889 --personnel-port 18892`; only 18879–18999 are accepted. Standalone helpers retain their usual fixed origins. The runner starts and stops only its own loopback servers and uses isolated browser profiles. Player servers, profiles and saves remain untouched. Logs, screenshots, exported saves and `report.json` go into a new ignored `.local/reports/shared-acceptance-*` directory. Use `--out reports/my-acceptance-run` to choose another new ignored directory.

Every stage must pass and report the exact browser-loaded JavaScript hash. The aggregate also records source commit, uncommitted state, source-content fingerprint, pinned toolchain, per-stage logs and complete web-file hashes. A source or artifact change during the run fails acceptance. A supplied build may be reused with `--web-root <directory> --expected-hash <main.dart.js SHA-256>`; the report labels it as supplied rather than claiming it was compiled from the current source. The default command builds its own artifact.

Journal-header regressions in `organisation_journal_test.dart` exercise original L/M/R/V/0/X journeys, source-first badges and explicit HQ scope, every optional Alt route, footer routing back from Agenda, pending-draft and required-report guards, modal/search/name isolation, unchanged campaign/RNG during navigation, and reachable labels at desktop and 1024×720/150%. The keyboard browser helper checks original L opens Agenda, W returns from that reader without advancing a day, and X saves from headquarters. It also navigates by optional Alt chords, saves through Alt+X, and checks Alt+W cannot advance a prepared order. Bare source keys retain their current-reader meanings.

`journal_navigation_state_test.dart` pins historical section IDs and source routes and exercises deferred HQ returns, controller completion without a later console revision, intervening required reports, explicit navigation/reentry, native chapter retention and session activation. The full-shell Newspaper → day command → original monthly funding report journey also runs at desktop and 1024×720/150% in `organisation_journal_test.dart`: Options cannot hide its acknowledgement, monthly totals reset only afterward, and the usable Organisation view and game focus return. The supplied monthly boundary is a declared test condition.

## Classic keyboard parity

The contract and audited reader families are recorded in [Classic keyboard audit](CLASSIC_KEYBOARD.md). `classic_keyboard_parity_test.dart` replays identical physical key sequences through the actual Classic `ConsoleWidget` and graphical shell from the same declared fixture and RNG seed. Every awaited checkpoint compares the source screen, complete action metadata, navigation, profile/order context, printed buffer, campaign JSON and matched RNG probes. Native text compares visible pending edits, then the source result after finishing. The journeys cover asset review and roster/profile return, ordinary/sleeper immediate choices, report paging and story acknowledgement, Agenda, travel and cancellation, held-key repeat, rename and prefilled text.

`classic_ledger_keyboard_parity_test.dart` covers every source page and Back alias, one-page any-key acknowledgements, original caller return, pointer-retained focus and isolated history. `classic_base_keyboard_parity_test.dart` compares source investment purchases and Back in Classic, graphical keyboard and pointer-started graphical journeys. `classic_menu_labels_test.dart` checks exact title/creation action keys, case-sensitive badges and profile page hints. These files run through shared acceptance. Pointer previews keep their separate campaign/RNG, stale-action and cancellation checks.

## Browser regressions

`scripts/browser_support.mjs` supplies `createQaPage` for disposable browser setup. It closes the preceding context, creates a fresh context/page and records page, console and request errors with the current scenario metadata. Each journey still owns navigation, expected-reader waits, fixture declarations and assertions. Use it when extending mission, siege or car-pursuit helpers so setup and failure cleanup stay consistent.

### Prepare an isolated web build

For the common creation/orders/navigation/save journey, the [shared acceptance runner](#shared-acceptance-journey) already owns compilation, ports and cleanup. Use this setup for a supplemental helper. Install Node.js/npm and the Edge/Chrome browser required by that helper, and complete [Development mode](BUILDING.md#development-mode) first.

`python scripts/developer_doctor.py --browser` inventories the SDK and locked browser-helper dependencies without launching or building anything. It reports missing setup separately from failures in the journey itself.

From the repository root, compile into a new ignored directory and inject its offline manifest once. The absolute output path avoids Windows shader-compilation failures with relative custom output paths. This leaves the player build and server on port 8765 available.

```powershell
npm ci --prefix upstream/tool/offline_test
if ($LASTEXITCODE -ne 0) { throw 'Browser dependency installation failed.' }
. ./scripts/common.ps1
$flutter = Get-LcsFlutter
$dart = Join-Path (Split-Path $flutter) 'dart.bat'
$buildId = (Get-LcsSourceCommit).Substring(0, 8)
$qaWeb = Join-Path (Get-Location) ('.local/reports/browser-qa-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '/web')
Push-Location upstream
try {
    & $flutter --suppress-analytics build web --release --no-pub --no-wasm-dry-run --base-href / `
        "--output=$qaWeb" "--dart-define=LCS_BUILD=$buildId" --dart-define=LCS_CHANNEL=Development
    if ($LASTEXITCODE -ne 0) { throw 'QA web build failed.' }
    & $dart run tool/inject_service_worker.dart $qaWeb
    if ($LASTEXITCODE -ne 0) { throw 'Offline manifest injection failed.' }
} finally {
    Pop-Location
}
$expected = (Get-FileHash (Join-Path $qaWeb 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
```

Choose the helper's standalone port below. Start only an unused port, retain the same `$qaWeb` and `$expected` throughout the run, and run helpers sharing an origin sequentially. Each helper uses disposable storage. The shared acceptance runner manages its own alternative ports; those overrides do not apply to every standalone helper.

| Port on `http://127.0.0.1` | Standalone helpers in `scripts/` |
|---|---|
| 18879 | `browser_review.mjs`, `creation_browser_review.mjs`, `first_week_browser_review.mjs`, `recruitment_browser_review.mjs`, `keyboard_interface_browser_review.mjs`, `screen_browser_review.mjs`, `mission_browser_review.mjs`, `street_clinic_browser_review.mjs`, `car_chase_browser_review.mjs`, `siege_browser_review.mjs`, `discord_feedback_browser_review.mjs` |
| 18881 | `injury_browser_review.mjs` |
| 18882 | `personnel_browser_review.mjs` |
| 18883 | `catalogue_browser_review.mjs`, `juice_browser_review.mjs` |

For example, start the 18879 server and run the Organisation journey:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch.ps1 -Port 18879 -NoBrowser -WebRoot $qaWeb
node scripts/browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

The launcher checks `/__lcs_launcher_health` and rejects a port serving a different directory; helpers compare the actual browser-loaded JavaScript with the expected hash. Keep the web files unchanged during QA and rebuild after source changes. To check an extracted player, use its `web/` directory as `$qaWeb` and recompute `$expected` instead of compiling another player. When finished, stop only the server started for this task with `scripts/stop.ps1 -Port 18879` (substitute the chosen port). The specialty examples below assume this setup and their matching port.

### Equipment and vehicle artwork

`catalogue_art_qa_test.dart` checks all 32 equipment paintings and all 11 vehicle types against the retained PNGs, runtime manifests and provenance. It checks complete transparent crops, decoded row/detail paintings, legacy item IDs, exact passenger/driver action metadata, disabled controls, and unchanged campaign state/RNG. Its shared application-cache journey covers guides and rows at desktop, 1024×720/150% and 360×640/200%, followed by the actual weapon-shop and dealership purchase handlers. Set `LCS_CAPTURE_SCREENS=1` to retain the contact sheet and source-handler screenshots under ignored `reports/catalogue-art-qa/`.

`scripts/catalogue_browser_review.mjs` requires its own isolated origin, **http://127.0.0.1:18883/**, and an exact compiled `main.dart.js` SHA-256. Use the [isolated web build](#prepare-an-isolated-web-build) above; keep existing player and QA servers separate. Start that directory with `scripts/launch.ps1 -Port 18883 -NoBrowser -WebRoot $qaWeb`, then run `node scripts/catalogue_browser_review.mjs --expected-hash $expected`. The helper imports a declared disposable copy of the bundled campaign with stored items and eleven vehicles, exposes actual inventory choices, all three guides and dossier equipment at desktop and 150%, and compares complete exports before/after inspection. Asset responses and loaded JavaScript hashes are checked. Prepared possessions are not earned gameplay outcomes; native Windows GUI acceptance remains separate.

### Tactical artwork

`tactical_artwork_test.dart` checks known-object and hazard sprites, null metadata for hidden terrain, hover/tap inspection, adjacent direction commands, disabled movement callbacks, and unchanged complete campaign/map state and RNG. The existing tactical, interaction, full-floor and field-plan layout suites retain engine visibility, exact tile hit coordinates, zoom isolation and compact 150% text checks. `runtime_art_test.dart` decodes all atlases and checks exact source/runtime alpha and native colour fidelity.

`tactical_visual_review_test.dart` uses explicitly prepared map geometry and loads the real runtime atlases before rendering. Set `LCS_CAPTURE_SCREENS=1` to save desktop, compact and atlas review PNGs under ignored `reports/tactical-artwork/`. These are rendered widget fixtures, not an earned gameplay journey.

`tactical_supplemental_qa_test.dart` independently checks all 28 supplemental room states across local and full-floor snapshots, unchanged campaign/RNG, unknown terrain and graffiti-neighbor isolation, native 32-pixel sprite identity, joined presidential desk quadrants, combined visited/fire/trap cues and shared image-cache navigation. `tactical_supplemental_visual_test.dart` captures the 16 paintings beside legacy artwork at 32 and 64 pixels, live wall lettering/status combinations, desktop and compact maps at 150% text, and the full-floor map. With `LCS_CAPTURE_SCREENS=1`, these explicitly synthetic presentation fixtures write to ignored `reports/tactical-supplemental/`; they do not claim earned gameplay or a native Windows application playthrough.

`tactical_snapshot_layers_test.dart` checks occupied-tile features, hazards, restrictions, action guidance and isolation from unknown neighbors. `tactical_legend_test.dart` checks the complete scrollable key at enlarged text sizes. `full_site_map_inspection_test.dart` checks passive inspection after transformed zoom/pan, floor changes and short panes. The tactical layout tests require readable default cells and initially visible current-tile guidance, without scrolling to make the assertion pass.

`tactical_shell_acceptance_test.dart` exercises twelve full-shell scenarios in one application-cache lifetime at desktop and 1024×720/150%. It deliberately restores background game focus while presentation dialogs and menus are open, then tests F/U/G and arrow keys against the same pending reader and complete campaign/map/RNG state. Optional captures under `reports/tactical-acceptance/shell/` are explicitly synthetic. `tactical_actions_flow_test.dart` runs the actual `siteMode` loop against declared synthetic geometry: stairs change floor, G transfers real loot and clears its marker, safe refusal returns to the field, and passive fixtures disable manual Use. The door journey declares Security 50 to guarantee an unlock, checks the standing marker during cancellation and success, then enters through the opened door. Other field fixtures retain the original skills and RNG. `safe_retry_test.dart` supplies Security 1 and then 50 to deterministically test failed attempts, successful retries and one-time rewards for all four safe types. Bulk pawn journeys cover mouse confirmation, cancellation, keyboard Escape and revisiting at both desktop and enlarged layouts. Shop buyer journeys verify initially visible crew choices, cancellation and reopening, then two purchases going only to the selected buyer.

`scripts/mission_browser_review.mjs --only tactical --expected-hash $expected --out reports/tactical-acceptance/browser-final` checks the rebuilt game on isolated port 18879. It follows actual building entry, door opening, combat, retreat and exit using the original fixture's capabilities, plus full-map return, map-key keyboard isolation, compact focus/fit/pan recovery, safe inspection and exact save/reload/reimport continuity. Its 1024×720/150% chapter also opens and closes a crew dossier, checks control bounds and blocks original movement/fight/flee/use keys behind inspection. This option stops after the tactical journey; the broader `operation` option also follows any resulting medical treatment and omits the dedicated compact map chapter.

`tactical_loot_qa_test.dart` independently checks dropped-stack snapshots, unsearched/hidden-content isolation, exact catalogue identity, condition and cash labels, door-origin positioning and unchanged campaign/RNG. It exercises local maps, full-floor inspection and item-detail dialogs at desktop and enlarged/short layouts with the real decoded artwork. Set `LCS_CAPTURE_SCREENS=1` to retain the explicitly prepared presentation captures under ignored `reports/tactical-loot-independent-qa/`. The actual G-reader journeys in `tactical_actions_flow_test.dart` separately check both combined unsearched/dropped loot and an illustrated dropped pile, including transfer and marker removal.

### Juice visibility

`juice_status_test.dart` checks negative and positive rank boundaries, alignment exemptions, recruitment limits, stage progress, verified activity caps and pure inspection. `juice_indicator_test.dart` checks current benefits, next milestones, help on pointer/keyboard/touch, enlarged/mobile layouts, accessible Juice sorting and unchanged live-reader/campaign/RNG state. Existing dossier, crew, recovery and recruitment suites also cover the shared indicators.

`scripts/juice_browser_review.mjs --expected-hash $expected` uses a fresh Edge context and the dedicated QA origin `http://127.0.0.1:18883/`. Prepared characters cover Juice 160 and a mix of higher/lower ranks. The journey checks identities, the report inspector and dossier, click/tap help, directory sorting, 1024×720/150% reading and complete before/after campaign export equality. Build into a separate ignored directory and serve it with `scripts/launch.ps1 -Port 18883 -NoBrowser -WebRoot $qaWeb`.

### Personnel directory

`personnel_directory_test.dart` checks every filter, deduplication, full status/location labels, cross-category search, empty results, large rosters, keyboard/semantics, and small/enlarged layouts. `organisation_journal_test.dart` follows hospital patients and off-page characters through the original profile readers, retains search/filter state, checks focused search does not issue game shortcuts, and preserves native roster tools, squad rules, campaign state and RNG.

`scripts/personnel_browser_review.mjs --expected-hash $expected` checks the rebuilt game on its dedicated isolated origin `http://127.0.0.1:18882/`. It imports an explicitly prepared mixed-status fixture in a fresh browser context, exercises Clipboard/search/filters/profiles at normal and 150% reading size, and compares complete before/after campaign exports. Launch that QA directory with `scripts/launch.ps1 -Port 18882 -NoBrowser -WebRoot $qaWeb`; keep player saves and servers separate.

### Injury status

The dossier's medical plate is a read-only view of existing body state. `injury_status_test.dart` checks every special injury, actual modifier and treatment distinction, all wound flags, nonhuman anatomy, and unchanged campaign/RNG. `crew_injury_panel_test.dart` checks hover previews, pinned selection, keyboard activation, named touch controls, simultaneous organ callouts, deceased records, and dossier layouts at 1280×800, 1024×720/150%, and 390×844/200%.

```powershell
Push-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub test/injury_status_test.dart test/crew_injury_panel_test.dart test/crew_dossier_test.dart
Pop-Location
node scripts/injury_browser_review.mjs --expected-hash $expected --out reports/injury-status-qa/browser
```

The injury helper pins its own isolated origin, `http://127.0.0.1:18881/`, so it can run alongside the existing recruitment/screen QA server on 18879. Launch the rebuilt QA web directory with `scripts/launch.ps1 -Port 18881 -NoBrowser -WebRoot $qaWeb`, and compute `$expected` from that directory's `main.dart.js`. It uses a disposable campaign copy with explicitly prepared wounds, checks the rendered map and details at normal and enlarged reading size, and compares complete exports before and after inspection. Its synthetic injuries are display fixtures, not injuries earned in gameplay. Keep player saves and player servers separate.

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

`--large` uses 1024×720 and 150% journal reading size. Each observed screen records
its controls, text and screenshot; failed routes remain in the report and fail
the command. The helper requires the same isolated port as the other browser checks.

`remaining_screens_playtest_test.dart` and
`orders_social_screens_playtest_test.dart` additionally render real source handlers
through `MainApp` at desktop and 1024×720/150%. They exercise safehouse upgrades,
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

### Organisation, opening week and creation

These helpers use the [isolated build](#prepare-an-isolated-web-build) on port 18879. Keep `$expected` tied to the same served directory, including when checking an extracted player.

`browser_review.mjs` checks dossier skill hierarchy, portrait-age repair, mechanics disclosure, retained order categories, repeated assignments, contextual travel labels, Clipboard dossiers and equipment pages at normal and enlarged text. Export comparisons verify that inspections/cancelled drafts preserve the campaign and repeated confirmations change only the intended members' assignments. Screenshots and JSON results are written under ignored `reports/`.

The first-week journey uses a separate synthetic campaign with old wanted crimes cleared and one explicitly ready prospect. It exercises the join decision, squad formation, weapon transfer, assignments, a real free shop visit, seven day advances, earned money/Science training and exact export/reimport continuity in a fresh browser context. It does not claim to earn the prospect's persuasion or manually certify native Windows gameplay.

```powershell
node scripts/first_week_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

Use the compiled `main.dart.js` hash from the extracted release player when checking that player. Both helpers keep browser profiles isolated from player saves.

Founder creation uses an installed Chrome and an exact compiled-build hash:

```powershell
node scripts/creation_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

The Organisation and first-week helpers use installed Microsoft Edge; creation uses Chrome. The creation helper checks portrait rerolls, continuity through creation/headquarters/save reload, projected answer-bonus help and click-through, and public-name placement below the question. It covers manual and random backgrounds at normal size and 1024×720 with 150% text. Unit regressions cover all 50 source bonuses, untouched state/RNG/ID counters during previews, and the birthday/cohort edge case. Use only the isolated QA port when stopping a test server.

Portrait semantics can update before decoded art paints. The creation helper waits for the selected atlas cell's pixels before comparing rerolls, with a bounded deadline and retained first/last/reference captures, identities and distance samples. A placeholder or another cell cannot satisfy that readiness check; the original visual-change and unchanged-settings assertions still apply.

For an offline boot check, run `node upstream/tool/offline_test/test_offline.mjs "$qaWeb" /`. Set `LCS_BROWSER_CHANNEL` to `msedge` or `chrome` to use an installed browser. This helper owns a temporary loopback server and fresh profile, requires every resource in the current version's scoped cache, then stops its server, disables networking and requires the original title again. Actual loaded-script hashes must match online and offline; failures retain unique ignored captures and diagnostics. This checks offline startup; saved-campaign continuity and native GUI acceptance retain their separate journeys.

### Mission, recovery and custody

Use the [isolated build and server setup](#prepare-an-isolated-web-build) on port 18879. Its `$qaWeb` and `$expected` must describe the same unchanged build.

```powershell
node scripts/mission_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
```

The mission helper travels into an actual police building, moves through its entrance, waits for an encounter, inspects a field dossier, exercises escape-direction retry/cancellation, fights and retreats using current UI controls. Exports verify ammunition consumption and headquarters return. Any wounds actually sustained are taken to the university hospital and advanced through treatment until discharge or a recorded siege interruption. Separate prepared campaigns exercise unarmed political conversation, paid/unpaid hospital care with bleeding, and a month-end custody transition through police transfer, trial and prison release. The report declares all prepared conditions, including wounds, funds, custody status and dates; prepared arrests or persuasion are never described as earned through play.

If an earned police siege blocks day advancement during actual-injury care, the helper records the siege and still-admitted patients explicitly and preserves that campaign snapshot. It does not claim discharge or resolve the siege by altering state. The separate prepared care scenarios continue to check discharge; siege resolution is outside this helper's coverage.

Each resolved scenario saves and exports through the original menu, reloads the browser, and imports into a fresh storage context. Whole-campaign equality covers character condition, portrait identities, equipment/ammunition, squads, orders, funds and campaign progress. Conversation keeps desktop speaker/participant selection, then exercises political choices, invalid input, acknowledgements and any source-offered cancellation at 1024×720/150%, checking action bounds and return to the operation. Hospital/court pages also use compact enlarged reading. Screenshots, decision frames, declared prepared inputs and exported saves remain under ignored `reports/`. `--only tactical|operation|conversation|paid-care|unpaid-care|custody` helps investigate one scenario; the full acceptance run omits this filter.

The helpers locate installed Edge/Chrome in standard Windows directories and accept `--browser-executable <path>` for another installation. They never download a browser, reuse a player profile or clear player storage. Field-input regressions cover retries, source identity/revision checks, the original movement exception and keyboard isolation while inspecting. Recovery regressions cover billing, affordability, conviction records, exact persistence, responsive journal routes and read-only details. These checks do not certify every injury, pursuit, siege, trial outcome or native Windows path.

### Street arrest and Free Clinic

```powershell
$expected = (Get-FileHash (Join-Path $qaWeb 'main.dart.js') -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/street_clinic_browser_review.mjs --expected-hash $expected
```

This helper closes the earlier street-arrest and Free Clinic coverage gaps. It starts a healthy campaign copy with no wanted charges, removes a non-founder's clothing through the actual equipment controls, assigns donation collection, and advances the original daily checks until police accost the member. The normal indecency check and gameplay RNG remain unchanged. The browser inspects the pursuit dossier, retries an invalid key and surrenders through the current source action at 1024×720/150% text. State observations verify the new charge, interrupted income, police custody, confiscated weapon/ammunition, cleared order, original squad cleanup and founder remaining at headquarters. The arrest is produced during play rather than inserted into a fixture.

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

Run these supplemental gameplay browser helpers sequentially for a complete acceptance pass, keeping fresh-context startup loads separate. The shared acceptance runner schedules its own six journeys with the worker limit described above; this does not make other fixed-origin helpers safe to run together. Preserve failed/interrupted reports as well as successful final reports. These paths do not certify every siege faction, escalation, generated map or campaign ending; native Windows GUI checks remain separate.

## Release checks

Each build report records automated command exit codes and source identity. Generated reports and old test counts are not a substitute for a current run. Review the build log and release-specific metadata for what actually ran.

```powershell
python scripts/verify_package.py 'release/<build>/<extracted-package-folder>'
```

Keep its ZIP and `.zip.sha256` beside the extracted folder. Verification checks the manifest, file inventory, paths, archive SHA-256 and each ZIP member's contents/CRC.

Before describing a release as manually accepted, test its extracted launcher, campaign creation, load/save/export/import, assignments, day advancement and any changed gameplay path. Browser offline claims need cache activation plus a save/reload with networking disabled; server-stopped claims need the test server actually stopped. Native GUI and clean-machine launch checks are separate from compilation and browser results.

Historical reports are retained in Git history, old release artifacts and local ignored evidence. Published previews keep their original verification scope; later source or packaging changes do not retroactively certify them.
