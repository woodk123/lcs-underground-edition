# Presentation and release review

## Current Gangsters journal delivery — 14 October 2026

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


## Historical navigation and space-use pass — 1aa0be78

Reviewed the current source against both upstream Git base `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87` and the previously reviewed corresponding source in `release/LiberalCrimeSquad2026-20261013-223621-63cac78e/source/upstream/`. Eleven original source files differ from that prior package: nine were already modified and two (`basemode/liberal_agenda.dart`, `common_display/common_display.dart`) become newly modified originals relative to Git. The retained rule/data inventory now has 23 reviewed original source changes and 11 added modern modules. Original recovery/calendar/ending changes, all authored XML/maps/assets and the 31 generated serializers match the previous accepted source bytes.

The new original-source delta consists of per-await navigation declarations, stable activity/category/bulk IDs and actor/eligibility presentation metadata, plus the dedicated Operations section exit. The original handlers still perform every assignment, equipment transfer, travel, cancellation, political update and simulation result. Category opening can choose an original suggested task; the UI explicitly says so. Assignments apply immediately while daily or monthly effects follow the original timing.

| Reviewed contract | Finding and evidence |
|---|---|
| Safe section navigation | `ConsoleNavigation` is a capability for one audited await. `getKeyEvent` finally, `erase` and scoped `replaceActions` clear it. Base equipment/vehicle lists, roster/profile lists, assignment menus, ongoing Agenda and archived media explicitly opt in. Recipients, quantities, squad assembly, generic paged prompts, tactical equipment and forced victory Agenda remain outside it. Real reader tests check the live capability and unchanged date, funds, roster and RNG. |
| Operations queue preservation | `Key.menuExit` is reserved `U+E000`; planning handles it by returning before manual Back logic. Both city and district-level section exits keep the same queued activity object and random stream. The original manual Back still returns one level; manual Cancel at the root clears the visit. |
| Mechanics help | IDs are authored at the real menu rather than inferred from prose or shortcut letters. Regular and sleeper contexts remain distinct, including monthly infiltration and daily return to active service. Bulk policies explain per-person selection rather than pretend to be a single activity or guaranteed payout. Source checks covered actual music skills, class price/training limits, teaching supply caps, hacking/fraud teams, prisoner factors, sleeper exposure/return requirements and raw heat/secrecy thresholds. Help previews preserve the serialized campaign and the next 12 random rolls. |
| Nonmodal inspection | HQ and generic person portraits call the shell inspector; city crew/squad/building inspectors use bounded adjacent or lower panes. Inspection never dispatches a game command. The explicit Full dossier opens the complete record. A review finding corrected idle squad wording: squad `none` now says the personal assignment applies and no longer presents Lay Low as its override. |
| Space and essential controls | Compact HQ puts five live crew in the first 1040 × 610 content viewport, uses only three routine quick actions, and keeps actual W wording, current Cancel Departure, Save & exit and siege responses exposed. Other original commands remain reachable in More. City uses direct district opening, persistent building names, fitted occupied bounds and inspector space only when needed. Desktop/sidebar and narrow strip navigation remain available during audited management waits. |
| Final assignment/header friction fixes | Only a typed regular/sleeper confirmation with a resolved actor and mechanics enables the compact task header. It hides the old rows 0–9 from the main flow while preserving the original rows 1–9 (equipment, attributes, skills, wounds and transport) in an in-place read-only expansion. Name, title, blood and recorded prior income remain visible; campaign funds stay in the shell. The exact original confirm action is placed at the header and excluded from subsequent choice groups, producing one Done control. Accepted nontext button commands clear the stale crew pane to free the new workspace; rejected/stale commands and text Escape preserve its state. |
| Specialized reader return controls | Removing the generic footer exposed a pointer dead end for the complete article body when the original Any Key action was nonempty. The modern shell now supplies one header Continue only for a valid modern article DTO, and one Back to operation only for the modern full-map marker. Both dispatch Enter to the original reader; archived articles accept any key, daily story dismissal accepts original Back/Enter, and full map accepts any key. The footer remains suppressed for these specialized bodies and ordinary DirectContent choices stay duplicate-free. Classic rendering keeps its existing controls. |
| Command and information fidelity | HQ, direct-content and city order callbacks guard current revision and action identity, use exact source keys and honor disabled state. Read-only inspectors use authored person/place IDs; untyped or duplicate names cannot select another entity. The original fog/movement/article paths remain unchanged from the previously reviewed snapshot. |

Executed seven focused suites against the navigation/inspector source freeze:

```text
flutter test test/menu_navigation_metadata_test.dart test/mechanics_help_test.dart
  test/headquarters_view_test.dart test/hq_dossier_test.dart
  test/modern_app_test.dart test/city_planning_view_test.dart
  test/crew_dossier_test.dart --reporter expanded
84 tests passed
```

Log: `reports/ux-navigation-review-tests.log`. The final assignment-header/accepted-command deltas subsequently pass **11 tests** in `reports/ux-assignment-header-review-tests.log` (`section_navigation_test.dart` and `hq_dossier_test.dart`), with clean focused analysis of both runtime files and both suites. These suites overlap the earlier count and the full suite. The real `assignTask` regression verifies visible Done before y=220, exactly one control, preserved facts on expansion, unchanged campaign/revision while expanding, and original exit behavior.

The specialized-reader return fix passes both pointer regressions in `reports/ux-specialized-return-review-tests.log`, with clean focused analysis. The article case uses the nonempty original Any Key metadata; the full-map case runs in `GameMode.site` with section navigation disabled and verifies one clickable return. These tests establish the reader contract; final browser traversal still belongs to the current candidate's QA report.

The final pinned audit passes with zero failures: 200 original Dart files retained (177 unchanged, 23 reviewed exact hashes), all 76 original XML/map/other-art/font/license/credits files unchanged, 11 modern modules, 31 original-model generated serializers and 11 added asset/font files. The assignment/header freeze changed only its two reviewed modern files, and the subsequent specialized-return correction changed only the shell; every other original/addition pin still matches. Final shell SHA-256 is `fc8e599b9023307983b5600eb12e320b9610fc15f0a45d2694422ca1dbcca1a8`; direct-content SHA-256 is `9b17d9fe19828d1b50f35ab17de9d95db7a7df5b3a3041247c5d068e1cdabec2`.

This is source/widget/real-reader evidence. It is not certification of the new build's packaged browser flow, screenshots, offline cache/upgrade, ZIP identity or native GUI. Those final gates must cite the current build hash; earlier `63cac78e` browser/package evidence remains historical. No native UI automation was resumed after the user's stop instruction.

## Earlier presentation review — 13 October 2026

Reviewed on 13 October 2026 against the working source in `upstream/`. This review covers the modern presentation boundary, command identity, tactical information and package contents. The original Dart gameplay engine is intentionally retained; this is not an audit of a rewritten simulation.

## Result

Nine actionable defects were corrected across the initial presentation review and follow-up end-state/modal testing. All 16 focused regression cases now pass against the integrated fixes; no unresolved blocker remains within this reviewed scope. The final build and package snapshot must include these changes. This source and focused-test result does not replace the broader final-package gates.

## Corrected findings

| Finding | Player impact | Integrated correction and evidence |
| --- | --- | --- |
| Focused buttons lost Enter/Space activation | Tab to Start a new movement, then Enter forwarded the literal engine Enter command instead of N. The same ancestor input handler intercepted other focused controls. | `lib/modern/modern_app.dart:122` lets focused descendants receive activation keys. Actual Tab traversal tests verify Enter and Space dispatch N, and Enter opens the focused guide without a game command. |
| Hidden classic input remained in the focus traversal | The retained Offstage console could receive Tab focus. On the mobile platform its invisible text field sent Backspace to the awaiting engine before the visible choice was reached. | `lib/modern/modern_app.dart:325` excludes the hidden console from focus. An Android platform regression test traverses the visible modern controls and verifies no engine input before activation. |
| Physical Page Up/Down were discarded | The engine supported their pagination mappings, but the modern key filter rejected their null-character events. Widget reproductions received no command. | `lib/modern/modern_app.dart:145` accepts Page Up/Down. Windows platform tests verify the engine receives `[` and `]`. |
| Equipment's descriptive Cursors label became C | The original equipment menu uses `Cursors` to describe ammo allocation. Taking its first letter exposed a modern button that selected the third inventory item. | `lib/engine/engine.dart:73` exposes separate Up/Down ammo actions. The regression preserves the real inventory C action and verifies the arrow commands. Unknown multi-character descriptions no longer become arbitrary letters. |
| Recruitment's Enter/Escape label became E | Clicking Call it a day selected the fifth recruit when present, or did nothing, instead of ending recruitment. | Named alternatives normalize to the first supported named key in `lib/engine/console.dart`. The regression verifies Enter dispatch while preserving candidate E as a separate choice. |
| Ending totals counted active saves twice | High-score saving merged totals that already included active saves, then added the completed campaign again. Unrelated active campaigns also leaked into persisted completed totals. | `loadHighScores(includeActiveCampaigns: false)` is used for persistence, while the normal display still includes active progress. Both real ending tests assert every cumulative field, and a second active-save case verifies separation without changing score rules. |
| Daily advancement used 24 elapsed hours | Spring daylight saving left the campaign clock at 01:00; autumn could return to 23:00 on the same displayed calendar date. | `nextCampaignDay` constructs the next calendar date and preserves UTC inputs. Spring/autumn helper tests and the 87-day campaign test verify calendar identity. |
| Side-panel Continue discarded edited text | Typing Avery over Alice then clicking Continue accepted Alice because the field's edits had not reached the engine. | The text-mode button now says Confirm text and submits the field through the original text reader. A real widget regression verifies Avery is accepted. |
| Equipment recipient prompts retained inventory controls | Selecting loot A left A/S/Up/Down visible while the engine expected a numbered squad recipient. Those stale controls were ignored by that reader. | Explicit nested `getKey(choices: ...)` commands replace stale metadata. The passing real five-person fixture test selects loot A, records recipient choices, equips member 2 and verifies only that member changes. |

## Additional audited paths

- `Console.getKeyEvent` publishes each awaited frame and expires headquarters/tactical markers and actions when that decision is consumed. Nested notifications therefore use the readable decision view. `sendInput` rejects input while no decision is awaiting or when the previous input has already completed the pending reader. The existing bridge tests cover duplicate clicks, immediate listener dispatch, erasure and text-reader context.
- `printCars` registers separate lowercase passenger and uppercase Drive actions at `lib/basemode/base_actions.dart:135`. Case-sensitive dispatch preserves the uppercase character through the original vehicle reader. Generic button callbacks send the action's exact key.
- Tactical actions in `lib/sitemode/sitemode.dart` use the same availability conditions as the original instructions and engine handlers. The tactical marker is published after the map updates visibility; consumed decisions expire it. The full map has a dedicated marker and a graphical explored-floor renderer.
- `TacticalMapSnapshot` and `_describeTile` match the original `printSiteMapSmall` viewport and `drawTileContent` priority. Unknown tiles expose identical fog, enemies require the original LOS/camera conditions on known tiles, lock discovery remains hidden until known, and rendering does not modify exploration or LOS. The existing map tests cover the viewport edges, hidden information, tile priority, accessible labels and movement dispatch.
- Every `addOptionText`, `addInlineOptionText` and `addCenteredOptionText` key expression was inspected for descriptive or combined keys. Other static named keys are recognized. Dynamic keys are single letters, numbered page entries within 1–9, squad members within 1–6, or supported page/prefix forms. No additional wrong-command pseudo-key was found.
- Ordinary graphic overlays and the graphical full map render in the modern workspace. Mouse-driven specialist editors retain the classic renderer. Readable tactical rows suppress the old map region only while the tactical marker is active, leaving generic result messages intact.

## Package inspection

The web packager copies GPL v2, the full upstream authors list, modified corresponding source, generated serialization, the dependency lockfile, local assets, build scripts, documentation, build evidence and checksums. The inspected source snapshot includes the new font files and their Apache license. The native packager also includes explicit Roboto/Flutter notices, requires `NOTICES.Z`, and keeps the complete Flutter release runtime plus app-local VC runtime files.

Native QA packaging permits an unfinished source reference when `--source-package` is absent. Final distribution must supply the actual matching source companion and keep it beside the native package. The 20:49 web candidate predates this review's final keyboard/identity corrections; it is an earlier candidate rather than final evidence for them.

## Evidence and limits

Executed from `upstream/`:

```text
..\.tools\flutter\bin\flutter.bat test test/action_identity_test.dart test/campaign_endings_test.dart test/keyboard_navigation_test.dart --reporter expanded
16 tests passed

..\.tools\flutter\bin\flutter.bat analyze --no-pub lib/title_screen/high_scores.dart test/campaign_endings_test.dart test/action_identity_test.dart test/keyboard_navigation_test.dart
No issues found
```

The final focused test log is `reports/release-review-tests.log`. The widget tests use loaded production fonts, a 1280 × 800 viewport, real Flutter focus traversal and Windows/Android platform variants. Command identity tests reproduce the original equipment/recruitment option registrations and dispatch through the original input reader. A real equipment fixture additionally verifies the nested recipient flow and resulting outfit. They do not substitute for a complete gameplay run.

## Campaign endings and longer progression

`test/campaign_endings_test.dart` adds six passing cases using a valid shipped save, loaded original XML tables, isolated real Sembast storage and mocked preferences:

- An explicit terminal victory fixture sets every law, legislative/court seat and executive to Elite Liberal, and marks CCS defeated. The original `advanceMonth` executes Congress and `winCheck`, exposes the victory L choice, persists `Ending.victory`, deletes the completed save and throws `EndGameException`.
- A terminal defeat fixture uses the original roster death method, then calls the original `checkForDefeat`. It persists `Ending.dead`, deletes the save and throws the same launcher exception.
- Both endings invoke the original `titleScreen` after catching that exception. The real H action is enabled, Continue is disabled for the deleted save, and the score record and every cumulative statistic agree with the engine state. The unbounded outer launcher loop is not run by the test.
- Normal headquarters play advances from 4 January to 1 April 2023: 87 consecutive calendar days, exactly three monthly legislative cycles, unchanged roster IDs, one age increment per day, changed political state, news generation, Save & Exit and complete JSON round-trip through the actual saved campaign.
- Spring and autumn calendar transitions are verified for local dates and UTC values.
- A separate active campaign remains unchanged, contributes once to the displayed universal totals, and is excluded from persisted completed totals.

The terminal fixtures prove the preserved ending routes and semantic controls are accessible; they do not claim a player earned the victory prerequisites during these tests. Long-run balance, save migration, final native graphical operation, clean-machine installation and final offline browser behavior require their separate recorded scenarios and exact final package evidence in `RELEASE_CHECKLIST.md` and the delivery reports. Source retention alone does not demonstrate every specialist path has been tested.
