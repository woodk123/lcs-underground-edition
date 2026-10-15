> Historical verification record. Results below apply to the dated runtime and source hashes. Current player downloads, the separate source archive, packaging steps and preview coverage limits are documented in [BUILDING.md](BUILDING.md) and [WINDOWS_BUILD.md](WINDOWS_BUILD.md). Repackaging preserves the game binaries and adds no gameplay test coverage.

# Release acceptance and evidence

## Historical Gangsters journal delivery — 14 October 2026

### Final verified gates

Runtime `dbc3f95b0ac5cd4e68764def55281363787f0cb0960be77dac31e188b6bf4296`; offline cache `f21b649f` (123 manifest resources / 124 cache entries).

| Gate | Current evidence |
|---|---|
| Build | 352 tests, clean focused/full analysis; `.local/reports/build-20261014-022623/` |
| Source fidelity | Passed; 350 audited files; all 200 originals retained, 176 unchanged and 24 reviewed |
| Packaged Edge | 48 checkpoints, no skips/page/console/request errors; `reports/browser/journal-2026-10-14T02-29-59-157Z/report.json` |
| Chrome | 23 checkpoints, no findings/errors; `reports/browser/chrome-final-2026-10-14T02-28-45-166Z/report.json` |
| Enlarged reading | Independent 8-capture review with actual mechanics and crew scrolling; 800×600 at 150% |
| Persistence | Full campaign export comparisons, restart, original article, new campaign, real prior-profile upgrade passed |
| Offline | Packaged helper stopped; cached day/save/reload passed, 6 January 2023 / $11 |
| Windows | Compiled matching source in 29.9 seconds; final graphical playthrough remains unverified after the user's stop instruction |
| Distribution | Final source, GPL credits, font notices, generated-art provenance, verification evidence and archive integrity included |



This pass follows the user's later requirement for the first **Gangsters: Organized Crime** organiser, replacing the earlier broad inspiration. The full 104-page source/manual audit is in [GANGSTERS_MANUAL_AUDIT.md](GANGSTERS_MANUAL_AUDIT.md), the materials/layout specification is in [GANGSTERS_VISUAL_SPEC.md](GANGSTERS_VISUAL_SPEC.md), and current exact-runtime acceptance belongs to [GANGSTERS_JOURNAL_ACCEPTANCE.md](GANGSTERS_JOURNAL_ACCEPTANCE.md). `release/DELIVERY.json` identifies the accepted distribution and its matching source.

The organisation uses eight illustrated top tabs, direct squad portrait tabs, a selected-person/crew page, brass binding, facing pool/map and group/task rails beside the binding. Preparing an activity is a local draft; only Confirm dispatches the original action. Cancel keeps the previous assignment. Pool arrows and drag use the original allocation handler. Actual LCS skill, capacity, location, blood, equipment, cost and timing remain authoritative. Global reports use the full spread. Required engine readers retain their explicit controls and cannot be hidden by the local Options page.

The rendered campaign checks include exact saved-state equality for category browsing/cancel and pool round trips, actor-only order effects, squad-only visit effects, keyboard activation, source operations, process restart, actual newspaper stories, offline saves and a copied prior campaign upgrade. Final acceptance is recorded only after the no-skip packaged run; preliminary reports are identified as previews and do not establish that gate.


## Historical UI friction/space delivery — 1aa0be78

The primary browser runtime `1aa0be78906b3f97a0ef3cc8cbebb983ca15edb234ecb9c0da9da16b5ea2b82a` passes the current requested navigation, explanation and space-use pass. The matching Windows source compiles; final native graphical playthrough remains outside the verified scope. Current accepted archives and exact integrity reports are identified in `release/DELIVERY.json` and each package's BUILD_INFO/FILES/SHA-256 records.

| Current gate | Result |
|---|---|
| Build and source | 225 tests, strict/focused and full analysis pass; `.local/reports/build-20261013-233421/` |
| Fidelity | Passed with zero failures; all 200 original Dart files retained (177 unchanged, 23 reviewed), original authored data/maps/assets unchanged, 11 modern modules, 31 serializers and 11 added art/font files pinned |
| Layout | 25 checkpoints at 1600×1000, 1280×720, 800×700, five actual crew; `reports/browser/smoke-2026-10-13T23-36-30-298Z/existing-campaign/` |
| Packaged play | 87 checkpoints, zero skips/page/console/request errors; `reports/browser/smoke-2026-10-13T23-36-30-298Z/report.json` |
| Offline |Own helper stopped and endpoint unavailable before cached play, daily work, save and reload; worker 3db5f6fd / 116 cache entries |
| Existing campaign upgrade |Passed; exact cached runtime, prior founder/date/funds/activity and actual article retained; pointer Continue returns to archive |
| Native |Final release compiled in 27.6 seconds; `reports/final-windows-build.log`; graphical playthrough unverified |
| Distribution |Matching source, credits/license, asset provenance, current evidence and file/ZIP integrity checks included |

- [x] Crew details are nonmodal and routine section changes require one click from audited nested management menus.
- [x] Section switching preserves queued destinations; explicit original Cancel remains distinct.
- [x] Compact headquarters shows crew first; dates/funds and section navigation remain visible in narrow layouts.
- [x] Typed task/sleeper/bulk metadata drives accurate purpose, skills, requirements, costs, risks and timing without simulation rolls.
- [x] Done is visible at the task header; full original character facts expand in place. Selection applies immediately, execution follows source timing.
- [x] City/district opening uses one click; actual sites keep explicit inspect→queue semantics. Map/list remain usable alongside inspectors.
- [x] Specialized article/full-map bodies have explicit pointer continuation/return controls; generic duplicate footers stay absent.
- [x] Final native/web builds, source-fidelity review, packaged browser/save/offline/upgrade evidence pass within the stated scope.

`UI_FRICTION_ACCEPTANCE.md` is the current usability acceptance record. `BROWSER_QA.md`, `RELEASE_REVIEW.md` and `GAMEPLAY_FIDELITY.md` explain methods and limits. Earlier release decisions below belong to their dated runtimes and are historical evidence.

## Historical city-extension acceptance — 63cac78e


## Release decision

The **primary browser package is accepted** on runtime `63cac78e154023a26e8519c62b1237360fcf5219de7ddc02700415ea2fcc54f2`. It fulfils the clickable city/building, explicit orders, crew portrait/dossier and generated animation extension while retaining the complete original simulation. All required implementation and primary acceptance gates below are closed. The additional native Windows build compiles; its final full graphical playthrough remains unverified because the user stopped native UI control.

## Identity

| Item | Final evidence |
| --- | --- |
| Frozen build | `.local/reports/build-20261013-221335/`: 174 tests pass, strict/focused and full analysis clean, release build/offline injection pass |
| Runtime | `main.dart.js` SHA-256 `63cac78e154023a26e8519c62b1237360fcf5219de7ddc02700415ea2fcc54f2` |
| Browser | `reports/browser/smoke-2026-10-13T22-19-06-594Z/report.json`: 81 captured checkpoints, zero skips/page/console/request errors |
| Upgrade | Same report folder's `upgrade/report.json`: real prior campaign preserved, final cache hash verified, original archived article opened |
| Offline | Worker `76ce1d07`, 115 manifest resources/116 cache entries; actual helper shutdown then offline play/save/reload |
| Toolchain | Flutter 3.47.7 revision `abaf9c523780a608bd46686fd5e53740a07077f8`; upstream base `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87` |
| Archive identity | Delivered `BUILD_INFO.json`, `FILES.sha256`, adjacent ZIP `.sha256`, external integrity reports and `release/DELIVERY.json`; documentation/evidence attachment may change archive hashes without changing the tested runtime |

## Eight acceptance contracts

1. [x] **Building world.** Default City streets contains generated isometric buildings on painted streets, rather than cards over a panorama. Original available locations become directly inspectable objects; zoom/fit and the equivalent Locations list work. All five locations fit at 1280×720.
2. [x] **Inspect before ordering.** Clicking a building opens local inspection without changing date, funds or current squad order. An explicit original Enter district/Queue squad visit control dispatches the action. A queued visit can be cancelled without executing it. Exact-hash supplemental inspection proves Need Car and a disabled order; the complete fresh campaign honestly records when none are unavailable.
3. [x] **Real orders and consequences.** Central assignments change the real activity. An actual Nano Pixie Internet Cafe order executes through the retained daily engine, enters tactical mode, responds to equipment/door/pointer/keyboard commands, and returns to HQ on 3 January. Full-floor graphical zoom/fit also works.
4. [x] **Crew portraits and factual dossiers.** HQ, assignment-row and city crew portraits open Overview/Skills/Campaign record. Founder blood matches HQ at 220/220 in the final browser scenario, and inspection changes no campaign state. Typed person IDs and duplicate-name/no-guess regressions protect identity; portraits are illustrative rather than procedural biological reconstructions.
5. [x] **Generated animation.** Three production ChatGPT-generated atlases supply 40 source cells: 16 building objects, 16 portraits and eight walk frames. Actual browser screenshots/video show animation (nine distinct full-scene states in 24 samples); reduced-motion matched pixels remain unchanged. Widget tests cover eight-frame progression, hidden/offstage/ticker/lifecycle behavior and unavailable-order semantics.
6. [x] **Modern direct interaction and readability.** Central people/tasks/equipment/destinations are actual controls; detached modern Available choices duplicates are absent. Tab→Enter, staged text input, proportional text, center selections and feedback pass. City/dossier fit at 1280×720; HQ/tactical cover 1280×720, 1600×900 and 1920×1080, with enlarged-reading HQ/guide at 800×600.
7. [x] **Campaign persistence and offline delivery.** Real download/export, empty-context file import, invalid-import preservation and full browser-process restart pass. The actual managed package helper stops and its endpoint is unavailable before offline reload/play/save/reload reaches 4 January/$8. Prior QA Founder/4 January/$1004/Laying Low and the original KILLER FOOD story survive the update on the same origin with exact final cached bytes.
8. [x] **Retained depth and reproducible release.** Full source/fidelity, tests, pinned SDK/build and reviewed assets pass. Original simulation, specialist compatibility views, content, maps and data remain present. Primary distribution is a real extracted standalone browser package; source, GPL license, authors and provenance accompany the release.

## Automated source and engine evidence

- [x] 174 tests pass with clean focused/full analysis. Dedicated suites cover captured command identity/case, alternatives, enabled state, stale revision, modal recipients, text focus, central tables, graphical maps, articles, crew identity/dossier, city scene and animation contracts. See `upstream/test/` and `RELEASE_REVIEW.md` for actual suite scope.
- [x] Fidelity audit passes with zero missing originals: 200 original Dart files (179 unchanged, 21 reviewed changes), unchanged original XML/map/art/font inventories, nine modern modules, 31 generated serializers and 11 added art/font files pinned. Exact reviewed hashes and negative probes are documented in `GAMEPLAY_FIDELITY.md` and `FIDELITY_AUDIT.json`.
- [x] Original progression fixtures cover 87 consecutive days, three monthly cycles, roster IDs/aging, politics/news and save round trips. Explicit original victory/defeat fixtures cover ending controls, score persistence, cleanup and title return. Fixtures establish exercised contracts; they do not claim an entire naturally earned winning campaign.
- [x] Five shipped save files, legacy migration, future/truncated/invalid input, rollback, failed writes, pre-day/save-exit guards and RNG preservation pass. Trials and other original subsystem contracts are documented in the review. Simulated failure fixtures do not claim every OS quota/permission failure was physically reproduced.
- [x] Launcher reuse, conflicting-root refusal, mismatched-PID refusal and matching shutdown have recorded evidence. The original player origin remains `http://127.0.0.1:8765/`; localhost is separate storage. QA uses only isolated 18876 profiles and helpers.

## Evidence and coverage boundaries

`BROWSER_QA.md` gives exact final report/capture paths, methods and reproducible commands. Supplemental Need Car evidence comes from the same frozen runtime before a later obsolete driver text matcher; the containing final corrected scenario passes independently. Earlier builds remain historical, rather than being relabelled as final.

Warm headless Edge observations sampled 120 frame intervals each: HQ p50/p95/max 4.2/4.3/12.5 ms, city 4.2/4.3/4.4 ms and tactical 4.2/4.2/12.4 ms. These are browser frame-delivery/heap observations, not hardware throughput or a large-campaign benchmark.

- The city is an illustrative navigable representation of the original currently listed destinations. Sprite walkers are decorative; no new travel or campaign rules are implied.
- Portraits are a stable finite illustration bank. Actual age, condition, equipment, skills and orders are source-backed dossier data.
- Browser coverage is bounded first-session/public-operation/save/offline acceptance, supported by deeper engine fixtures. It does not certify every origin, combat/arrest/hostage/siege branch, long roster, localization/zoom combination, map layout or decades of balance.
- Native compilation and packaging are additional deliverables. Final native graphical playthrough/layout coverage remains unverified after the user's stop instruction; no further native UI automation occurred.
- Physical hardware benchmarking, browser storage eviction and every operating-system failure mode are disclosed coverage limits, not silently open required implementation work.

## Distribution verification

Final packaging attaches this exact report, screenshots, animation, upgrade and supplemental evidence while preserving runtime bytes. `scripts/verify_release.py` checks ZIP sidecar hashes, file manifests, CRC/inventory and reviewed source/art identities. Generated external integrity reports and `release/DELIVERY.json` identify the final web/native archives. This document does not embed circular archive checksums.
