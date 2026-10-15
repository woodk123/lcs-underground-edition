> Historical verification record. Results below apply to the dated runtime and source hashes. Current player downloads, the separate source archive, packaging steps and preview coverage limits are documented in [BUILDING.md](BUILDING.md) and [WINDOWS_BUILD.md](WINDOWS_BUILD.md). Repackaging preserves the game binaries and adds no gameplay test coverage.

# Browser QA

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


## Historical navigation and usability acceptance — 1aa0be78

**PASS: 87 packaged browser checkpoints, 25 five-person layout checkpoints, zero skips, page errors, console errors or failed requests.** Runtime SHA-256: `1aa0be78906b3f97a0ef3cc8cbebb983ca15edb234ecb9c0da9da16b5ea2b82a`. Worker `3db5f6fd` caches 116 entries. Final rebuild `.local/reports/build-20261013-233421/` passes 225 tests and clean focused/full analysis.

Evidence: `reports/browser/smoke-2026-10-13T23-36-30-298Z/report.json`, its `existing-campaign/report.json`, and `upgrade/report.json`. The latter includes seven screenshots. `UI_FRICTION_ACCEPTANCE.md` describes the current screen/interaction contracts and exact evidence. Earlier sections below retain their original runtime identities.

The current package was launched through its own Play.cmd at isolated port 18876, in a dedicated headless Edge profile. The player's 8765 origin/profile was untouched. Checks cover nonmodal crew inspection, one-click city/district opening, nested assignments-to-Media navigation, a queued visit preserved through Operations/Media/HQ, source-backed task explanations and immediate Done, explicit 125% reading size, and pointer returns from the specialized full floor map and actual archived article.

The actual campaign changes 1→2 January and $7→$12 through daily work, executes a public Spielberg Park visit, exercises tactical pointer/keyboard/equipment/full-map controls and returns on 3 January. The package helper is then stopped; cached offline reload, another day, save and reload recover 4 January/$12. Export, empty-context import, invalid-import preservation and browser process restart pass. These observed earnings are one campaign result, not a payout forecast.

The fresh campaign had no selectable archived story in the inspected state. The same-runtime upgrade therefore supplies actual article acceptance: the existing QA Founder, 4 January/$1004/Laying Low and KILLER FOOD story survive, +12.8% displays with the exact source effect retained in accessible metadata, and pointer Continue returns to the same archive. No news/story or player state was fabricated.

The 25-checkpoint five-person campaign review covers 1600×1000, 1280×720 and 800×700. Root directly inspected task, HQ, crew and building inspectors and city/list captures. The generated walking animation produces eight distinct raster states in 24 samples; reduced motion produces zero changed pixels. Original sprite/portrait provenance remains in CITY_SPRITE_ASSETS.md.

These are bounded browser/engine contracts. Final native graphical playthrough remains unverified after the user's stop instruction; the current native source compiles. Exhaustive branches, hardware benchmarking, browser storage eviction and every long-roster/localization combination are not claimed.

## Historical city-extension acceptance — 63cac78e


## Accepted build and method

**PASS: 81 captured checkpoints, zero skips, no uncaught page errors, console errors or failed requests.** The complete corrected driver tested an actually extracted package, launched by its own `Play.cmd` on isolated port 18876. The browser is headless Microsoft Edge 155.0.4283.45 on Windows.

- Runtime SHA-256: `63cac78e154023a26e8519c62b1237360fcf5219de7ddc02700415ea2fcc54f2`.
- Report and screenshots: `reports/browser/smoke-2026-10-13T22-19-06-594Z/report.json`.
- Build evidence: `.local/reports/build-20261013-221335/`, **174 passing tests**, clean strict/focused and full analysis, successful release build and offline injection.
- Tested package: `LiberalCrimeSquad2026-20261013-221429-63cac78e`, extracted under `.local/package-qa/` with its same-named top directory.
- Service worker: `76ce1d07`, 115 manifest resources and 116 cached entries including the root document.

The driver uses browser input, real editable/file controls, rendered semantics, cache/storage APIs and browser performance APIs. It does not call Dart game methods, inject game fixtures or edit player saves. Each fresh smoke uses an isolated persistent QA profile. Final package attachment changes documentation/archive checksums without changing these tested runtime bytes; read the delivered `BUILD_INFO.json`, `FILES.sha256`, ZIP sidecars and integrity reports.

## City and crew acceptance

The default City streets view renders generated isometric **building objects on streets**, with the original locations represented by clickable objects. It is no longer cards over a panorama. At 1280×720 all five current city locations fit in the street viewport; the crew strip and inspector remain accessible. Zoom in enlarges the real building objects and Fit city restores the view. Locations list remains an equivalent accessible navigation view.

Building clicks open local inspection. The separate Enter district/Queue squad visit buttons then dispatch original commands. Inspection and zoom preserve visible date, funds and the squad order. Actual district/site selection queues a visit without advancing the day; Cancel Departure clears it. A later real public-site order executes through the original daily engine.

The complete random campaign exposed no unavailable local building. Exact-runtime supplemental evidence captures Eastern Washington, Need Car and a disabled order from the preceding frozen-build run: `supplemental/disabled-building-order.png` and `supplemental/evidence.json`. That specific inspection passed unchanged state checks; the run later stopped on an obsolete driver copy matcher. The corrected complete 81-checkpoint run passes independently. No unavailable state was fabricated.

HQ portrait, central assignment-row portrait and city crew portrait controls open factual Overview, Skills and Campaign record dossiers. The founder's **220/220 blood** matches the visible HQ record in the final campaign. All tabs close without changing date/funds; city dossier inspection also preserves Laying Low. The same dossier is captured at 1280×720 with its close control visible and scrollable content. Source/widget contracts separately prove typed person IDs, duplicate-name isolation and no name-based identity guessing.

## Actual generated animation

The three ChatGPT-generated production atlases contain **40 source cells**: 16 building objects, 16 portraits and eight walk frames. The walking atlas visibly animates in the city. Twenty-four real browser samples produced **nine distinct full-scene raster states**, up to **546 changed pixels**. This counts rendered scene states, not individual atlas cells. Source/widget tests establish the eight-frame sequence; the actual browser captures establish visible playback. With reduced motion enabled, matched captures changed **zero pixels**. Building and walking atlas resources were observed loaded by the browser.

`city-animation/city-animation.webm` is encoded from real JPEG browser samples at their measured average rate (about 6.95 fps); PNG samples and timestamps are retained. It is a short evidence clip, not a fixed-rate engine recording. Decorative pedestrians do not change campaign time or simulate travel. Widget tests additionally cover hidden/offstage, ticker, reduced-motion and disposal lifecycle behavior.

## Retained gameplay, saves and offline operation

Keyboard Tab→Enter opens the guide and starts a campaign. The actual staged founder field replaces its prefill. Central person row → Legal Fundraising → Solicit Donations → confirmation changes the real assignment. Daily work advances 1→2 January 2023 and funds $7→$8. Roster, agenda and media navigation do not advance time.

An actual Nano Pixie Internet Cafe visit reaches the tactical view. Real pointer equipment/ammo controls produce engine feedback; the squad opens the door, activates an adjacent map tile, moves from column 36/row 2 to column 36/row 3, returns by ArrowUp and exits to HQ on 3 January. Full-floor Zoom in enlarges actual map tiles and Fit floor restores them. HQ and tactical captures cover 1280×720, 1600×900 and 1920×1080; the 800×600 HQ/guide also exercises enlarged reading size.

Save & exit plus complete isolated browser-process close/relaunch preserves founder, activity, date and funds. A real download exports the campaign. An empty separate context imports through the actual file chooser and restores it. Truncated JSON is rejected while the valid campaign remains loadable.

The driver matches managed health directory, package metadata and local/served JavaScript bytes, stops that extracted package's own helper, and verifies its endpoint is down. With networking disabled, cached application reload, another actual day and save/reload succeed: **4 January 2023/$8**. Application caching and campaign persistence are separate checks.

## Real prior-campaign upgrade

`upgrade/report.json` is also **passed**. It reuses only the isolated previous QA profile originally recorded at `smoke-2026-10-13T21-06-05-742Z`, already upgraded through b0, on the same 18876 origin. It verifies cached main bytes equal the final SHA above and worker `76ce1d07` is active.

QA Founder, 4 January 2023, $1004 and Laying Low survive the update. The existing source-generated KILLER FOOD article opens with **+12.8%** primary impact and exact value retained in accessible metadata. No synthetic story or save was created. The upgrade helper was stopped afterward. Player browser profiles were never accessed.

## Screenshots and observations

Important final captures are `29-city-building-streets.png`, `33-city-streets-1280x720.png`, city dossier tabs 30–32 and 34–36, `37-city-building-zoomed.png`, `38-city-animation-verified.png`, `39-city-planning-list.png`, the actual building-inspection/order captures, tactical/full-map screenshots and `offline-play-save-reload`. The `upgrade/` folder includes the preserved campaign and original article.

Warm 120-frame browser observations record HQ p50/p95/max 4.2/4.3/12.5 ms, city 4.2/4.3/4.4 ms and tactical 4.2/4.2/12.4 ms. Used JavaScript heaps were 54,651,372, 67,747,130 and 75,628,326 bytes. These measure headless browser frame delivery and heap, not GPU throughput or a large-campaign benchmark. Included `launcher-contracts.json` records helper reuse, conflicting-root refusal, mismatched-stop refusal and matching shutdown from the dedicated launcher checks.

## Reproduction and limits

Install Playwright dependencies and its matching FFmpeg component under `upstream/tool/offline_test` (`npx playwright install ffmpeg`). Extract the candidate and launch its own `Play.cmd -Port 18876 -NoBrowser`. From the checkout:

```powershell
node scripts/browser_smoke.mjs --url http://127.0.0.1:18876/ --package-root <absolute-extracted-package> --stop-server
```

Use no keyboard-skip flag. `scripts/browser_upgrade.mjs` accepts the dedicated prior QA profile, package root and output directory; never use a player's profile. Playing the distribution requires neither Playwright nor FFmpeg.

The 174-test build has deeper engine/domain/widget fixtures described in `GAMEPLAY_FIDELITY.md` and `RELEASE_REVIEW.md`. Browser acceptance is a real bounded first-session/public-operation/save/offline scenario. It does not claim every campaign branch, map, origin, long-roster/localization combination or decade of balance was manually played. Street positions are illustrative; decorative people do not represent actual crew movement. Portraits use a stable illustrative bank while factual age/condition/equipment/orders remain in dossiers. Native Windows compilation succeeds, but its final full GUI playthrough was stopped at the user's request. The primary accepted delivery is the browser package.

Earlier b0, 97df1dc9 and driver-diagnostic runs remain dated evidence for their own identities. They are not substituted for this final passing run.
