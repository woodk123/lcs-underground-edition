# Organisation journal visual and usability review

Reviewed 14 October 2026 against the original **Gangsters: Organized Crime (1998)** organiser. Initial, c6f41f84 and packaged deb1f3db/dbc3f95b browser builds were inspected. Source findings are resolved against the final audited snapshot below. The final dbc3f95b browser report passes all 48 checks; direct scaled-raster observations and practical reading-size limits are recorded separately.

## References and method

- Original native 640 × 480 screenshots: `00904_lieutenants.png`, `00906_lieutenants.png`, `00909_lieutenants.png`, `00910_lieutenants.png` in `D:\Programming\Gangsters\remake\assets\imported\media\tutorial\`.
- Actual selected-team capture: `D:\Programming\Gangsters\compatibility-fix\reconstruction-control-20261007\promotion\new-lieutenant-selected.png`.
- Official local manual: `D:\Programming\Gangsters\original-local\Manual.pdf`, specifically tutorial pp. 11–14, organiser/orders pp. 33–41, and allocation pp. 63–66.
- All twelve images in the [official GOG gallery](https://www.gog.com/en/game/gangsters_organized_crime).
- Source review of `organisation_journal.dart`, `journal_city_plan.dart`, `organisation_controller.dart`, `modern_app.dart` and `journal_theme.dart`.

Historical source risks are distinguished from rendered defects. Dispositions below identify the evidence and retain any final release verification still needed.

## Corrected reference interpretation

The original **order subtype rail sits immediately to the right of the binding, before the map**, at approximately x 348–380. A separate map utility rail sits at the outer right edge, approximately x 598–627. Native screenshots 00909 and 00910 establish this. An early suggestion to move the subtype rail to the outermost edge was incorrect and has been withdrawn; the visual specification now distinguishes both rails.

The original job card belongs **below the selected leader card on the left page**. The crew/skills paper is lower on the same page. Choosing a resource changes the right page while retaining the selected team on the left.

## First integrated browser evidence

Inspected `reports/browser/journal-2026-10-14T00-35-54-037Z/`, including initial organisation, prepared order and pool screens at 1600 × 1000, 1280 × 720 and 800 × 700. Runtime JS hash was `6e1f4f305f762f01d59b251f366543227d1cf8952c6244339417cc05ecdbc854`. This is explicitly a preliminary prototype, not final acceptance: its report ends with a missing accessible pool-member action and must not be presented as an all-pass release result.

Rendered strengths confirmed against the native reference: one open book, olive ivory surfaces, red spine and brass rings, eight pictorial top tabs, period portrait bank, a lower-left crew sheet, left job card, four inner order groups, and concrete activities beside the binding. Footer date/funds match the actual imported campaign (4 January 2023, $7). No invented wages, lieutenant stats or weekly workload gauge appear. The UI consistently uses serif text rather than terminal text.

The browser report confirms one-click squad selection without entering assembly, and reports that preparing then cancelling an order leaves the source campaign payload unchanged. These behavioural checks are reported as preliminary evidence; the full final campaign/browser suite remains required.

## Findings and disposition

| ID | Priority | Finding and evidence | Required check / recommended resolution | Status |
| --- | --- | --- | --- | --- |
| J01 | High | The initial fixed rail risked overflow with large text. | Keep all controls reachable in bounded regions. | Resolved in final dbc3f95b: 800 × 600 at 150% retains readable mechanics space and reachable Confirm/Cancel; actual wheel scrolling reaches remaining mechanics/crew. See final follow-up below. |
| J02 | Medium | Initial city title and map/index controls were duplicated. | Keep one title and toolbar. | Resolved and visually verified in c6f41f84 screenshots 09/13. |
| J03 | Medium | Separate shell/controller person selections risked a stale inspector. | Close or follow selection when changing people/squads. | Resolved: final deb1f3db nonmodal inspector screenshot 12 and actor-switch screenshot 21 show the correct live person; exact-actor confirmation/save proof passes. |
| J04 | Medium | `_poolPage` initially used all candidates, risking current members on both pages. Original Pool contains unallocated people. | Prefer members on the left and unassigned/available candidates on the right, with Remove on the left and drag-to-pool as an alternative. | Resolved in first prototype: screenshot 11 has four members left and only unassigned Yann right |
| J05 | Medium | Initial skill sorting omitted the selected rating from pool rows. | Show real skill values without changing state/RNG. | Resolved and visually verified in final deb1f3db screenshot 15: Firearms sorting, Firearms 2 in the candidate row and matching detailed skill values. |
| J06 | High | Narrow windows and larger text require deliberate page layout. | Do not clip controls or shrink body text. | Resolved within inspected desktop sizes: final dbc3f95b independently captured at 1280 × 720, 800 × 700 and 800 × 600 with 150% text. Small enlarged views use scrollable mechanics/crew; all facts remain reachable. Title and Agenda independently pass 360 px / 150%; organisation at 360 px was not raster-certified. |
| J07 | Medium | The initial prepared task showed an assigned check before confirmation. | Distinguish prepared and assigned states. | Resolved in c6f41f84 screenshots 09/13: a prepared hourglass is shown. |
| J08 | High | A removed pool candidate initially remained in the left team profile. | Restore a current team member; inspect candidates on the right. | Resolved and visually verified in final deb1f3db screenshots 15/18: Felix remains the selected left member, four current members remain left and unassigned Yann is inspected on the right. Pool round-trip save checks pass. |
| J09 | Medium | Initial narrow labels broke inside words. | Keep whole words or use ellipsis plus full tooltips. | Resolved and visually verified in c6f41f84 screenshot 13. |
| J10 | High | Initial job cards hid cost/risk/requirements behind an unmarked scroll area. | Surface essential mechanics before Confirm. | Normal-text finding resolved in screenshots 09/13. Final dbc3f95b enlarged views preserve the mechanics label and complete execution rule; longer factors/cost/risk require scrolling at 800 px / 150%, verified by actual wheel interaction. This small-window tradeoff is retained explicitly below. |
| J11 | Low | Initial full-page captures had an extra white overflow strip. | Verify actual viewport and raster dimensions. | Resolved in c6f41f84: every reported raster equals its actual viewport; fresh document metrics also match. |
| J12 | Low | City roofs are much larger and more uniform than the native organiser's densely varied roof/courtyard texture. | After usability fixes, vary decorative roof shapes, density and courtyards while keeping actual location IDs and clear labels. | Optional visual refinement |
| J13 | High | The initial prepared order hid the fifth crew row at 1280 × 720. | Compact the profile/card and retain six-person layout checks. | Resolved in c6f41f84 screenshot 09: all five fixture crew are visible beside the prepared card; full six-person tests retained. |

## Visual acceptance checklist

The integrated screen should be judged against all of these together:

- One physical open journal with olive ivory pages, a slim oxblood edge and red spine, three pairs of brass rings, and eight illustrated top tabs.
- Squad portrait tabs down the left edge with a clear selected outline. Selecting one changes squad context immediately.
- Period portraits and original pictorial icons, rather than the previous modern clothing bank or Material icons alone.
- Selected person/crew summary at upper left; job card below it; crew or skills paper at lower left.
- Four order groups at the inner edge of the left page, with the concrete activity rail on the inner edge of the right page and map to its right.
- Draft selection explains actual LCS mechanics before applying an order. Confirm and cancel operate on that prepared order; ordinary browsing does not silently assign a task.
- The right page changes between the actual city, pool, equipment and reports while preserving squad context.
- Labels and facts remain live, readable widgets at the available reading sizes. Pictorial art and texture carry no game text or hidden interaction.
- LCS quantities and timing remain truthful: squad capacity, real skill levels, real health, real resources and daily execution. No invented wages, weekly workload percentage or lieutenant simulation.
- Crew inspection, map browsing and group changes stay nonblocking. Required original text/destructive prompts remain explicit and retain entered state.

## Evidence to record after build

Capture the initial organisation screen, an open order group, a prepared order card, the crew pool with a selected candidate, another squad selected, a dossier interaction, and the 800 × 600 / 150% cases. Record exact paths and which issues were resolved, remain, or were disproven by the rendered evidence. Do not substitute the earlier non-journal release screenshots for this verification.

## Title menu delivery

`upstream/lib/modern/journal_title.dart` provides `JournalTitlePage(console, onAction, onHelp)`. Its wide composition is a newspaper introduction and campaign-menu page with journal binding. Narrow layouts put the actual actions first and scroll. It dynamically retains every source title action, including disabled states, the saved founder's Continue label, High Scores, Changelog, Mod Tools and unknown future choices. It forwards the exact action key and rejects retained callbacks after a revision/action/screen change. Tarn Adams, Ashley S. Fox and GPL-2.0 credit remains visible.

Ten focused title tests pass, including every enabled action at 1280 × 720, 800 × 600 and 360 × 640 with 100% and 150% reading size, independent Load/Continue availability, a future source action, Help, exact case-sensitive keys and a stale callback. Strict analysis passes. The integrated title was visually inspected in c6f41f84 screenshot 01; its journal presentation, live controls and credits are readable. Final release acceptance remains separate.

## Activity pictorial controls

The original uses painted concrete-order icons as well as painted section/group icons. `journal_order_icon.dart` and `journal_order_icons_v1.png` close that visual gap with sixteen original activity paintings in the same style as the navigation atlas. Each full-resolution symbol was inspected; source crops and exact activity mappings are recorded in the asset manifest. The artwork contains no controls or text. Four focused tests pass for exact enum mapping, all existing activities, offline transparent crop validity and nonblocking decoration; strict analysis passes.

## Follow-up source integration status

After the first prototype review, the root reports the following source fixes in progress or complete: full-spread global chapters, read-only city browsing before explicit visit preparation, removal of duplicate map toolbar, prepared-order hourglass, pool skill ratings and selected-left-member fallback, single-line labels, four separate resource buttons, and a skills toggle on the person card. The programmer owns a typed newspaper/media page to replace the generic source ASCII/Back-card grouping. These source reports are not yet final rendered acceptance; each will be checked against the next announced compiled runtime.

Additional isolated global-page captures are under `.local/reports/gangsters-research/global-pages/`. They use the same old prototype and therefore are historical evidence only. They show the generic media summary inside a Back action and global sections confined to the right page. A fresh 1280 × 720 context had exact 1280 × 720 document scroll dimensions, so J11 may be a full-page-capture/semantics artifact rather than a production viewport defect.

## c6f41f84 visual review

Inspected `reports/browser/journal-2026-10-14T01-28-56-237Z/` with runtime SHA-256 `c6f41f84fcd95b818f171496e805de79f155917d21af23f0cf6b60f19278c59f`. The title, prepared orders at 1280 × 720 and 800 × 700, Justice, Agenda, Newspaper, Reports and Options were reviewed directly. Raster sizes now equal their stated viewports. The prepared card displays source skill values, cost and risk; the pending activity has an hourglass; all five fixture crew fit on the left sheet. Activity paintings, period portraits and four resource modes now match the reference composition.

Newspaper uses the full spread with actual public opinion/support values and a separate Back control; it no longer turns statistics into a Back action. Justice has a truthful empty state. Options remains readable and retains explicit original campaign settings access. Reports' selected-squad scope was clarified in the final source heading. The c6f41f84 Agenda still contained raw terminal diagrams; this was the remaining high-impact chapter issue and led to the typed Agenda delivery below. The manual Ledger continuation defect in that preliminary run was separately fixed by the programmer. This preliminary run had a known workaround and ended in a failed browser step, so it is not cited as final all-pass acceptance.

## Typed Agenda delivery

`JournalAgendaView(console, onAction)` receives a read-only `AgendaOverviewFrame` from the actual ongoing `liberalAgenda` handler. It renders named executives and justices, the source chamber seat counts, labelled five-state law tracks and full law descriptions, and source survey percentages with separately labelled public interest. It retains all five source pages and their exact Previous/Next/Back/Disband commands.

Eleven focused tests pass: unchanged serialized campaign and next RNG rolls across all five pages; exact law descriptions and chamber totals; the original explicit disband phrase; both forced victory/defeat score-list exits with no ongoing metadata/navigation; stale-callback rejection; and all five pages at 1280 × 720, 800 × 600 and 360 × 640 with 100% and 150% text. Strict analysis passes. Forced endings continue through the original reader rather than displaying invented ongoing-government data. The root independently reviewed every source hunk and helper before freezing the change.

## Final source fidelity review

Compared the current source with accepted release `release/LiberalCrimeSquad2026-20261013-234134-1aa0be78/source/upstream/`, then checked the pinned original baseline `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87`. Delta inventory and individual diffs are retained under `.local/reports/gangsters-research/fidelity-delta/`. Engine/source approval was initially recorded for snapshot `57fdca8233414bc40c9d3bdb758a71414e3d419017bea14e509a7e44ea3abc24`. The final source snapshot is `263e08625993d7159d12f9d9a29541a01805063b8b0b01cb6dcfb285c6b073c5`; the subsequent change is the organisation reading-size layout repair described below, with no engine/gameplay/art change.

| Modified original source relative to accepted release | Audited modification |
| --- | --- |
| activate_regulars.dart / activate_sleepers.dart | Typed current-actor/confirmation/navigation snapshots and private read-only category preview commands. The private branch changes only local display category; original letter-key defaults, numeric task handlers, eligibility and timing remain. |
| base_mode.dart | Captures the actual source-authored W/F/C actions after rendering them. Scope invalidation refreshes the source menu; the UI does not invent siege/day/departure eligibility. |
| review_mode.dart | Annotates actual squad IDs and the fixed original allocation pool, member IDs and ready action. Same-location, mobility, capacity, original membership handlers, new-squad naming and empty-squad cleanup remain. Only the explicitly opened finance report opts into management navigation. |
| common_display.dart | Optional `onAwait` presentation callback, absent by default. Original pagination, choices and key dispatch remain. |
| media_overview.dart | Captures source-computed full headlines, dates, publication alignment, impact totals, unread state and exact commands. News generation/effects and the original read action remain. |
| liberal_agenda.dart | Ongoing-only capture alongside original printing; canonical chamber-count and law-description helpers; original poll statements forwarded through a helper that still calls the original `addstr`. No new political formulas. Original page handling, disband confirmation and forced score-list exits remain. |
| monthly/lcs_monthly.dart | Typed report rows and explicit manual-management navigation. Missing ledger entries are displayed as zero/omitted rather than `$null`; this changes report display/pagination only. Posting, monthly/daily accounting, fence valuation and automatic month-end acknowledgement remain. |

The four added engine context modules use immutable frame values and Console-keyed Expandos. They are not serialized game fields. Controller game changes dispatch only current source action objects and keys; category previews use a distinct private command accepted only by the corresponding source await. The original Console, engine reader, save/load code, game models, generated serializers, RNG implementation and daily/monthly resolution code outside the report function are unchanged relative to the accepted release.

One high-risk scope issue was found during review: legacy squad View and mobility-error prompts retained old person actions after a partial erase. It was fixed by requiring the exact live squad-ready action, and activity capabilities now require the exact confirmation plus navigation identity. Independently reran four real-reader regression tests after the fix; all passed: legacy View, mobility error, replaced activity capability, and required skill selection. These prompts cannot inherit allocation/order capability or be silently auto-exited.

`docs/FIDELITY_AUDIT.json` was independently read after the final pin update at 02:28:53 UTC: **passed**, zero failures, 24 reviewed original Dart changes, 176 unchanged original Dart files, 24 added modules, 31 pinned serializers and 19 added art/font files. Its complete current inventory totals 350 files. Original authored maps, XML, other original assets, original font, license and author credits remain unchanged.

No unresolved high-risk source finding remains in this reviewed snapshot. This source/data approval does not certify every runtime rule path; final compiled browser, offline, upgrade, save and packaged-build evidence remains the release gate.

## Final deb1f3db raster review

Inspected the final packaged runtime at `reports/browser/journal-2026-10-14T02-09-07-730Z/`, whose report identifies package `LiberalCrimeSquad2026-20261014-020340-deb1f3db` and main JavaScript SHA-256 `deb1f3dbd16944858fb69f98497a7bbf3a4727d858f9ae69facc3b831ae384c9`. Directly reviewed screenshots 01 (title), 09/13 (prepared orders at 1280 × 720 and 800 × 700), 12 (nonmodal inspection at 800 × 700), 15/18 (pool inspection and removal), 21 (prepared order after changing actor), and 24/26/27/28/29 (Ledger, Agenda, Newspaper, Reports and Options).

The prepared-card hierarchy now works at both inspected sizes. The selected actor, prepared state and hourglass, daily execution rule, actual skill levels, fee and police-risk explanation appear before the enabled Confirm button. All five fixture crew remain visible. The 800 px view retains the eight chapters, four group controls, resource controls and a single map toolbar. The long Operations label uses ellipsis rather than splitting inside a word. The current-member profile stays on the left while a pool candidate is inspected on the right, and the pool row exposes its selected-sort skill value. Switching to Eugene changes the job-card actor and actual skill values; the report separately verifies the resulting save changed that exact actor.

Ledger is now a full-spread financial record with aligned amounts, real cash/net/assets, an explicit inventory-valuation explanation and a separate Back control. Agenda is a full-spread political record with legible executive and justice names, House/Senate totals and labels, five-state law tracks, and original page/disband/back controls. Its scroll viewport permits the remaining laws below the fold; no source fact was replaced with a made-up summary. Newspaper has truthful opinion/support values and an empty archive state. Reports explicitly names the selected squad. Options presents reading size, guide, compatibility and campaign controls in the same paper surface. No new high-impact clipping, duplicate-control or blocked-navigation defect was found in these rasters.

The main browser journey records **39 passed checks**, including direct squad selection, prepare/cancel save invariance, allocation round trip, exact-actor order confirmation, all chapters, actual visit/tactical map return and browser-process save persistence. It then records a failed secondary archive-fixture step: the unchanged 2036 Moe campaign reached an original coma/constitutional-ending reader instead of the expected hospital or headquarters choice. The report contains no page errors, console errors or failed requests. This is accurately retained as a failed overall report pending the separate archive continuation/reload run; it is not cited as an all-pass release certificate.

Remaining visual refinements are low priority: the illustrative city has more uniform, coarser roofs than the native reference (J12), and the inline dossier uses a lighter sans-serif card than the surrounding journal. Both preserve truthful data and nonmodal interaction. Final organisation large-text raster, offline installation/update, and release-wide acceptance evidence remain separate checks; this review does not infer their results from normal-size screenshots or widget tests.

## Independent 150% raster follow-up

An independent isolated Edge context served the same immutable deb1f3db package on loopback port 18901. Evidence is `reports/browser/journal-large-text-2026-10-14T02-25-57-064Z/`. Six captures cover the initial organisation and prepared order at 1280 × 720, 800 × 700 and 800 × 600, all with the actual Options reading size set to 150%. The small driver reports its bounds/capture checks passed and no application errors; direct visual inspection found that those checks were insufficient to establish usability.

At 150%, deb1f3db's bounded job card left too little initial mechanics space: Uses/Cost/Risk were below the fold at 1280 × 720, and 800 × 600 showed only the actor/task/prepared header above Confirm. The header counts also clipped and the fifth crew member required scrolling. This reopens the large-text part of J01/J06/J10. The normal-text evidence above remains valid. The root independently observed the same defect and reopened only organisation layout dimensions, with a targeted regression for the mechanics viewport, readable timing and reachable confirmation/cancellation. A new package and direct scaled raster review are required before closing this follow-up; the old deb1f3db screenshots are not treated as large-text acceptance.

## Final dbc3f95b acceptance and scaled disposition

The final package is `release/LiberalCrimeSquad2026-20261014-022724-dbc3f95b/`, with main JavaScript SHA-256 `dbc3f95b0ac5cd4e68764def55281363787f0cb0960be77dac31e188b6bf4296`. The root's targeted layout repair reserves sufficient scaled job-card body space, bounds the prepared title/status, and keeps the profile counts visible. It changes layout only. The report `reports/browser/journal-2026-10-14T02-29-59-157Z/report.json` was independently read: **48 passed checks, zero failures, zero skipped checks, and no page errors, console errors or failed requests**. It includes actual prior-profile upgrade, server-stopped offline play, execution of the next campaign day, offline save/reload, new original campaign creation/continuation, populated original article and return, as well as the organisation/save/operation checks above.

Directly inspected this run's `14-prepared-order-800x600-reading150.png`, `41-original-news-article-in-journal.png` and `42-article-pointer-return-to-archive.png`. The actual article has legible publication, date, headline and Savannah body text in a bounded newspaper surface. Continue is a separate control and pointer return restores the populated archive with the actual impact figure.

Independent final-package evidence under `reports/browser/journal-large-text-2026-10-14T02-30-10-793Z/` covers initial and prepared organisation at 1280 × 720, 800 × 700 and 800 × 600 with 150% text. A second independent run, `reports/browser/journal-large-text-2026-10-14T02-32-48-384Z/`, adds actual mouse-wheel mechanics and crew scrolling. All eight capture/bounds checks pass, no application errors occur, and every raster equals its viewport. Direct inspection confirms that 800 × 600 now shows the complete daily execution rule, the labelled mechanics region and reachable Confirm/Cancel. Profile counts no longer clip. Scrolling the job card reveals the longer police-risk/confirmation explanation; scrolling the roster reaches the fifth crew member, Yann. The previously unusable mechanics viewport is resolved.

The enlarged compact view remains a conscious reading-size tradeoff: long names/tab labels use ellipsis with full tooltips/semantics, and factors/cost/risk plus additional crew may require vertical scrolling. They do not all fit simultaneously at 800 × 600 / 150%. This review approves reachability and readable content rather than claiming otherwise. At normal reading size the prepared card exposes timing, factors, fee and risk together, and all five fixture crew remain visible. No unresolved high-impact source or desktop-raster defect remains within the inspected scope; the original city-art density refinement and lighter inline-dossier styling remain optional improvements.
