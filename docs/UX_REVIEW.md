> Historical verification record. Results below apply to the dated runtime and source hashes. Current player downloads, the separate source archive, packaging steps and preview coverage limits are documented in [BUILDING.md](BUILDING.md) and [WINDOWS_BUILD.md](WINDOWS_BUILD.md). Repackaging preserves the game binaries and adds no gameplay test coverage.

# Usability review

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


## Current navigation, explanations and space — 14 October 2026

The current runtime is `1aa0be78906b3f97a0ef3cc8cbebb983ca15edb234ecb9c0da9da16b5ea2b82a`. Root directly inspected the final five-person campaign captures at 1280×720 and 800×700, including the task header, crew inspector, city map and site inspector. The browser visual suite passes 25 checkpoints with no page or console errors in `reports/city-review-2026-10-13T23-35-58.489Z/report.json`.

- All five crew fit the first headquarters screen at desktop sizes. A small overview replaces the tall banner, repeated metrics and six navigation cards.
- Sidebar and narrow navigation strip switch directly from audited nested management menus. Switching from Operations preserves the existing destination; explicit Cancel retains its original behavior.
- Crew inspection sits beside the workspace. Section changes and accepted nontext commands free that space automatically, including headquarters shortcuts. Full dossier remains an explicit optional detail view.
- Task screens show a compact actor/blood header and immediately visible Done. The original equipment/attributes/skills report expands in place. Contextual explanations show real skills, costs, requirements, risks and daily/monthly timing. Category defaults and immediate assignment changes are explicit.
- City and district controls open in one click; actual sites retain inspection followed by explicit queueing. The city uses the full width until an inspector is opened, and narrow inspectors preserve visible map/list controls and the order button.
- Date and funds remain visible in narrow windows. Reading size offers explicit 100%, 125% and 150% choices. Generic Continue/Back duplicates no longer consume space or imply a second confirmation. Specialized news articles and full maps retain one explicit continuation/return control; pointer regressions cover both.

The 225-test final rebuild and strict/full analysis pass. Source review corrected regular bulk navigation, text-prompt Escape priority, removed-person inspector state and idle-squad wording. Detailed current package/gameplay/offline evidence is recorded separately in `UI_FRICTION_ACCEPTANCE.md`; the following sections are historical evidence for earlier runtimes. Final native GUI playthrough remains unverified after the user's stop instruction.

## Current city extension decision — 63cac78e

The city is now a scene of individually selectable generated buildings on isometric streets, with zoom/pan and an attached inspector. Selecting a building is read-only; its explicit order enters the original district/city or queues the original squad visit. The detached panorama/card model is superseded.

Root directly inspected the final runtime's five-person existing campaign at 1600×1000, 1280×720 and the genuinely narrow 800×600 branch. All fitted buildings and the desktop order remain visible; narrow selection automatically reveals its inspector/order. Portraits open actual dossiers from HQ, the central roster and the city crew strip. Dossier content scrolls while its close control remains visible. Positive legacy ammunition with an unspecified type is described truthfully, and non-liberal captives do not receive an available-crew badge.

Current evidence is `reports/browser/smoke-2026-10-13T22-19-06-594Z/`: 81 packaged checkpoints without skips/errors, plus `upgrade/` and `existing-campaign/`. The latter contains actual five-person city/dossier captures and the 800×600 auto-reveal check. The animation recording and raster samples demonstrate visible frame changes; reduced motion produces no changes. The source regression covers offstage, resume and disposal. Full analysis is clean and 174 tests pass. Independent source/visual findings are recorded in `CITY_UX_V2_REVIEW.md`.

No blocker remains in the inspected city/crew interactions. These are bounded browser and engine checks; final native GUI playthrough remains outside the verified scope after the user's stop instruction. The following earlier review is historical context and is not evidence for the replacement runtime.

## Historical central-control baseline — b0b6e3b3

The reviewed release baseline meets the revised central-interaction direction. People, assignments and destinations are real controls in the main workspace; the detached generic “Available choices” rail is gone. Proportional tables/cards, a city planning board with an equivalent locations list, graphical tactical/full-floor maps and readable articles replace the common management DOS presentation.

No interaction blocker was visible in the inspected assignment, city, map, equipment, guide and HQ captures. The review found one concrete article presentation defect: a raw floating-point percentage wrapped its % onto another line. The correction displays the upstream one-decimal value and preserves the exact change in a tooltip/accessibility value. Its five focused tests pass, including the actual long-fraction regression. Root directly inspected the corrected real article in `reports/browser/smoke-2026-10-13T21-13-24-391Z/upgrade/05-upgraded-article-rounded-impact.png`: +12.8% fits cleanly. This capture belongs to final hash `b0b6e3b3`; the earlier baseline screenshots below retain their own identity.

This is a visual/usability review of the recorded first-session loop, not certification of every campaign outcome or specialist screen.

## Evidence inspected

All screenshots in this section were viewed directly from **reports/browser/smoke-2026-10-13T21-06-05-742Z/**. They came from the extracted package served by its own launcher at isolated port 18876, JavaScript hash prefix **a0c995ba**. The project manager reports **63 checkpoints, zero skips**, including an actual server stop followed by cached offline play/save/reload. See that directory's report for exact command/state evidence.

| Screenshots | Observed result |
| --- | --- |
| 08-headquarters-1280x720.png | HQ title, location, date, funds, principal day action and navigation are readable. The onboarding panel begins below the overview metrics; remaining HQ content scrolls. |
| 11-direct-people-table.png | The named person is a full-width central control. Skill, health, location and current activity remain in aligned proportional columns. Paging, sorting and bulk controls are central. No duplicated choice rail or ASCII header. |
| 12-direct-activity-categories.png, 13-legal-fundraising-options.png | Crew identity/stats precede directly clickable category and activity cards. Selected states have a border, checkmark and “Selected” label. Confirm is a prominent central action. |
| 22-news-article-first-review.png, 23-news-article-first-review-scrolled.png | Actual publication, date, headline, body and issue impact are legible. These baseline images expose the long-fraction percentage defect; they do not show the subsequent correction. |
| 25-city-planning-board.png, 26-city-planning-list.png | Real destination cards are directly selectable on the illustrated board and in a list alternative. Squad/current order, current location and “Need Car” are attached to their objects. The board explicitly says it is illustrated/not to scale. |
| 48-tactical-1280x720.png | Directional controls remain visible above the tactical panel at 1280 × 720. The current site, floor, alarm and squad position are readable. The map uses graphical tiles and tokens. |
| 51-tactical-full-map-pointer.png, 53-graphical-full-map-fitted.png | The full floor has graphical explored/fog state, zoom, fit, legend and a return instruction. No old party-buffer fragments surround the map. |
| 54-tactical-equipment-pointer.png | Equipment uses a central person table and real actions; “Unequip weapon” clarifies the row command. Ammo controls are visible separately. A remaining cursor-help note appears under the Strip card; this is a small grouping polish issue. |
| 42-field-guide-800x600.png | The compact guide explains foundation, planning and consequences in readable language. Its content scrolls while “Back to the game” remains visible. |

## Initial findings: current disposition

The earlier review was based only on reports/title.png and reports/options.png. Its findings are retained here with their present status instead of continuing to describe resolved defects as current blockers.

| Earlier finding | Status and current evidence |
| --- | --- |
| Siege W incorrectly labeled “Resolve siege”; F retained travel copy. | **Resolved in source.** HQ uses the engine's W label and gives the crisis F route fight/escape copy. A live siege is outside this screenshot run; no claim of manual siege acceptance. |
| HQ ignored squad-visit precedence and called blood general health. | **Resolved in source.** Squad visit descriptions take precedence; HQ labels blood explicitly and adds wounded/bleeding warnings. The reviewed baseline did not force an injury. |
| Text input appeared on ordinary menus and could send arbitrary command sequences. | **Resolved.** Explicit engine text-input state gates the field. The packaged browser run completed actual founder-name editing. |
| Ancestor keyboard handling could intercept text-field input. | **Resolved.** The entry focus has a guard; actual text editing and keyboard guide/new-game activation completed in the package run. Exhaustive modal/focus combinations are not claimed. |
| Trimmed terminal rows and independent row scrollers broke roster alignment. | **Superseded and resolved for modern management.** Screenshot 11 shows a real central table with proportional columns and a current-activity treatment. Narrow labeled-record behavior is covered by direct-content tests. |
| HQ omitted active squad identity and queued order. | **Resolved in source and contextual view.** HQ includes the squad name/activity; city captures show the selected squad and current order next to destination controls. Multiple simultaneous squads were not exercised here. |
| Setup settings hid their selected values away from their change controls. | **Resolved by direct-content cards.** Engine values and neighboring descriptions are attached to their choices. The source-backed campaign setup remains complete. |
| Active-person denominator included captives/dead and was called the network. | **Resolved in source.** The misleading denominator is removed. The overview now labels its count as active Liberals. |
| Creation navigation implied an active HQ despite disabled routes. | **Improved.** Generic routes remain visibly disabled during a decision, with a contextual return instruction; no unsafe base command is injected. This preserves the engine's nested flow. |
| Continue omitted founder identity; guide/text size reset on relaunch. | **Remaining low-priority polish.** Continue remains a generic campaign label, and guide/reading-size preferences remain session state. This does not block continuation, help access or the recorded save/restore loop. |

## Revised product assessment

The strongest Gangsters-inspired improvement is object-centered command: select the named crew member, choose their order, then confirm; select a real destination with its constraints beside it. The city board provides atmosphere and place context without claiming simulated geography or territorial rules absent from LCS. Its list alternative keeps the same choices accessible.

The assignment screen now solves the exact problem in the rejected screenshot. The main row itself opens the person's activity chooser. Selected categories and activities are visible where the player clicks. The cards preserve the original choices and disabled states while removing letter matching as a requirement.

At 1280 × 720, HQ navigation and day execution are visible. The overview illustration/metrics consume enough height that first steps and the crew/action sections require scrolling. The sidebar's Daily assignments and the always-available guide still provide a clear route. Tactical movement is pinned above the map instead of hiding below it. The full map deliberately starts as an overview; zoom/pan and fit controls explain how to inspect the small explored area.

News now uses an actual article layout rather than ASCII newspaper lettering. The body is the engine's full authored text and supports natural scrolling. The one-decimal display correction is necessary for readable impact cards and matches the upstream presentation precision; it does not alter political effects.

## Remaining polish and review limits

- The equipment Strip card retains “Cursors - Increase or decrease ammo allocation” as supporting text even though ammo has separate central controls. Moving that instruction to keyboard notes would make the grouping cleaner. The actual commands were available and worked in the recorded run.
- Continue could identify the founder/campaign, and guide/reading-size preferences could persist. These are improvements, not observed loss of save data or blocked navigation.
- The current reading-size control cycles approximately 100–120%; broader accessibility scaling remains a separate product improvement. Article tests explicitly cover 150% text at 800 and 1280 px, but that is not a manual claim for every screen.
- The baseline article precision screenshot is superseded by the inspected final b0b6e3b3 capture above. The actual previous campaign/story survived the upgrade; its exact effect remains in accessible metadata and the optional tooltip.
- Live siege/injury states, large multi-squad campaigns, all specialist interactions, campaign victory/defeat and exhaustive keyboard navigation were not manually demonstrated by these captures. Preserve the scope limits in the release checklist instead of treating retained source as proof of tested behavior.

The inspected first-session interface is coherent and directly usable. The remaining observed items above are specific polish or coverage limits; the prior inert-center/duplicate-menu problem is resolved.

