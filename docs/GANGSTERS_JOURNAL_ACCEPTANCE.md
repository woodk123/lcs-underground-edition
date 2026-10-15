# Gangsters journal browser acceptance

Date: 14 October 2026, Europe/London. Reference: the first **Gangsters: Organized Crime (1998)** organiser. This document records the completed browser acceptance for the delivered journal interface.

## Final result

**Passed: 48 checkpoints and 48 viewport-bounded screenshots; no skipped phases, page errors, console errors or failed requests.** The run started at 02:29:59 UTC and completed at 02:31:48 UTC (03:29:59–03:31:48 Europe/London).

- [Complete final report](D:/Programming/LiberalCrimeSquad2026/reports/browser/journal-2026-10-14T02-29-59-157Z/report.json).
- [Real cached-upgrade report](D:/Programming/LiberalCrimeSquad2026/reports/browser/journal-2026-10-14T02-29-59-157Z/upgrade/report.json).
- Tested extracted package: `.local/package-qa/journal-022724/LiberalCrimeSquad2026-20261014-022724-dbc3f95b`.
- Actual served and packaged `main.dart.js` SHA-256: `dbc3f95b0ac5cd4e68764def55281363787f0cb0960be77dac31e188b6bf4296`.
- Browser: isolated headless Microsoft Edge `155.0.4283.45`, using real Playwright pointer/keyboard controls.
- Final command used `--package-root` and `--stop-server`, with no preview, keyboard-skip or Ledger-bypass flags.
- The packaged launcher health endpoint identified the exact extracted `web` directory; its JavaScript hash matched the downloaded runtime.
- The isolated packaged server on **18876 was actually stopped** before offline play. The player's 8765 server/profile was not accessed or stopped.

The main report satisfies the packaging gate: `status: passed`, empty `skipped`, `pageErrors`, `consoleErrors` and `failedRequests`, the exact JavaScript hash, and `managedServerStopped: true`. The separate upgrade report records the same cached JavaScript hash and a preserved existing campaign.

## Actual campaign and method

The unchanged original `upstream/test/saves/felix_1_0.json` was imported through **Import a Save → Load & Manage Saves → Load Game**. It contains one five-member squad, 4 January 2023 and $7:

| ID | Actual crew member |
|---|---|
| 0 | Felix Kobayashi |
| 1 | Eugene Kaltenbrunner |
| 2 | Wendell McAllister |
| 3 | Nickie Somner |
| 4 | Yann Zedner |

The script uses rendered controls and accessible names, actual file chooser/download events, screenshots, mouse drags, native Tab/Space/Enter, and campaign exports produced by the ordinary save interface. It does not read Dart application variables, call game-engine methods, fabricate campaign state or inject game-state hooks.

Each run creates a fresh QA profile under `.local/browser-profiles/journal-<timestamp>/`. Upgrade verification copies a documented earlier QA profile into another fresh profile, leaving the source evidence profile intact. No human browser profile is used.

Every screenshot is captured with `fullPage: true`; the PNG dimensions must exactly match the viewport. DOM layout reports retain the document/body/Flutter-host dimensions and overflow observations. Screenshot clipping is not used to hide document overflow.

## Reference comparison

The [complete manual audit](D:/Programming/LiberalCrimeSquad2026/docs/GANGSTERS_MANUAL_AUDIT.md) records all 104 manual pages, source identity, page citations and the actual interaction sequences. Original references were inspected beside the final runtime captures:

| Original source | Final matching structure and behavior |
|---|---|
| [00904 — team and pool](D:/Programming/Gangsters/remake/assets/imported/media/tutorial/00904_lieutenants.png) | Left-edge squad tabs, selected leader/team card and lower-left roster; available people occupy the facing page. Portrait inspection and transfer remain inline. |
| [00909 — order selection](D:/Programming/Gangsters/remake/assets/imported/media/tutorial/00909_lieutenants.png) | Order groups at the inner edge of the left page; concrete activities immediately right of the binding; a pinned job card below the selected actor; target map beside the activities. |
| [00913 — selected target](D:/Programming/Gangsters/remake/assets/imported/media/tutorial/00913_lieutenants.png) | Blue selectable areas, red selected areas, actual target on a prepared job card, explicit local confirmation. |
| [00923 — report](D:/Programming/Gangsters/remake/assets/imported/media/tutorial/00923_lieutenants.png) | Selected-team context retained with its report and map. |

The runtime uses one leather-backed open journal, olive/cream paper, a narrow red binding and brass rings, eight pictorial section tabs, period portraits, lined roster paper and original activity paintings. Chapter labels, squad capacities, resources, skills, orders and daily timing use actual LCS mechanics. Runtime artwork and typography are newly authored; original Gangsters screenshots are reference material only.

The comparison verifies hierarchy, direct interactions and readability. It does not claim pixel-identical reproduction. The city plan represents known real destinations through an explicitly labeled illustrative block layout; decorative street positions do not imply simulated LCS geography.

## Verified interaction and save effects

All files below belong to the final [evidence directory](D:/Programming/LiberalCrimeSquad2026/reports/browser/journal-2026-10-14T02-29-59-157Z/).

| Check | Actual final evidence |
|---|---|
| Three normal desktop layouts | Captures 02–13 show initial organisation, direct squad selection, inline inspection and prepared orders at 1600×1000, 1280×720 and 800×700. All five roster rows and the confirmation control fit. |
| Enlarged reading at 800×600 | [14-prepared-order-800x600-reading150.png](D:/Programming/LiberalCrimeSquad2026/reports/browser/journal-2026-10-14T02-29-59-157Z/14-prepared-order-800x600-reading150.png). Actual Options controls select 150%; the timing text's bounds intersect a nonzero usable scroll pane and Confirm is inside the viewport. The script resets to 100% using the same controls before continuing. |
| One-click squad selection | Active vertical tabs select their existing squads without opening assembly. A second real squad is created through the original assembly/name prompt and both tabs switch directly. |
| Nonblocking crew inspection | Portrait opens an inline facing-page inspector. Switching Newspaper → Organisation clears inspection without a dismissal click. No modal dialog is present. |
| Groups, prepared order and cancellation | Personnel, Activism and Business are browsed. Donations is prepared and cancelled. The complete exported `saveData` object equals the baseline, including every serialized person, squad, site, vehicle, ledger/statistic and ID counter. |
| Pool selection, buttons and drag | Yann is removed, inspected in the right pool, added with the explicit control, dragged from pool to squad and dragged back to pool, then restored. The full exported game-state object equals its baseline after the round trip. |
| Native keyboard and exact actor | After Felix's draft is prepared, 19 native Tab presses reach Eugene's crew control; Space selects him and clears the prior draft. A new draft is prepared; 13 native Tab presses reach Confirm and Enter commits it. Full saved-game equality allows only Eugene's activity to change to Donations. |
| Reentry and cancelled replacement | Eugene's existing order is reopened; another task is prepared and cancelled. The entire exported game remains equal to the committed state. |
| Eight chapters and other commands | Ledger, Justice, Agenda, Newspaper, Reports, City maps, Options and Organisation are reachable. More headquarters commands exposes the original source commands. Ledger and Agenda are typed readable views; direct navigation succeeds without an extra Continue gate. |
| Target selection and queued visit | Actual known University District/Park locations are selected. Read-only City maps does not create a job until Prepare a squad visit. Cancelling preserves the previous full state. Confirm changes only the field squad's activity to the real visit target `Site19`; navigation preserves the queue. |
| Actual daily execution and operation | The queued squad arrives, enters the real tactical operation, opens View full map and returns through Back to operation, then leaves through the original result flow. The date becomes 5 January 2023 and funds become $9 in this actual RNG-driven run. |
| Full browser restart | The isolated Edge process closes and reopens. Continue restores the campaign; complete exported game-state equality proves preservation. |
| Original populated newspaper | [41-original-news-article-in-journal.png](D:/Programming/LiberalCrimeSquad2026/reports/browser/journal-2026-10-14T02-29-59-157Z/41-original-news-article-in-journal.png) displays the actual unchanged Moe archive's GM FOOD FAIRE, Cable News and Savannah, GA body. Accessible body text is asserted; the pointer Continue returns to the archive in capture 42. |
| New original campaign | Start a New Game reaches the original political-climate, random-origin and founder-name prompts. Journal QA Founder is created, saved and continued without a date/funds change. This random origin produced 1 January 2023 and $1000. |
| Real old-profile upgrade | The earlier QA profile's cached runtime `1aa0be78…` updates to `dbc3f95b…`. QA Founder, 4 January 2023, $12 and activity `none` are preserved and exported. Actual cache hash matches the final runtime. |
| Server-stopped offline play | The exact packaged helper is stopped and a network fetch confirms it is gone. Cached reload and Continue work; order browsing/cancellation works; the game executes a real day from 5 January/$9 to 6 January/$11, saves, reloads and preserves that result. |

The canonical comparisons are preserved as:

- `01-initial-canonical-save.json` / `02-cancelled-preview-save.json`: full game-state equality.
- `01-initial-canonical-save.json` / `03-pool-roundtrip-save.json`: full game-state equality.
- `03b-two-squads-before-order.json` / `04-confirmed-personal-order.json`: only the intended actor's activity changes.
- `04-confirmed-personal-order.json` / `04b-reentry-replacement-cancelled.json`: full game-state equality.
- `05-unconfirmed-target-save.json` / `06-confirmed-squad-visit.json`: only the intended squad's visit activity changes.
- `06-confirmed-squad-visit.json` / `07-queued-visit-after-section-switch.json`: full game-state equality.
- `08-after-real-operation.json` / `09-after-browser-process-restart.json`: full game-state equality.
- `upgrade/upgraded-campaign.json`: real older campaign preserved after cache upgrade.

The comparisons cover serialized campaign state. In-memory RNG state is not serialized; the separate [gameplay fidelity audit](D:/Programming/LiberalCrimeSquad2026/docs/GAMEPLAY_FIDELITY.md) and source/controller tests cover read-only no-RNG behavior.

## Earlier findings and disposition

Actual browser feedback led to repairs for inaccessible pool action names, missing native keyboard focus, cramped leader/job/crew layout, duplicate map controls, split narrow labels, semantic overflow adding blank borders, typed Ledger navigation and absent historical values, typed Agenda presentation, and article-body accessibility. The final run rechecks these repaired interactions against its exact packaged hash.

The 800×600/150% job-card body initially had zero rendered height. The final build reserves real mechanics space, keeps confirmation visible and permits scrolling within the remaining crew/details regions. The final enlarged screenshot and DOM clipping intersection verify that repair. Narrow labels use ellipsis and retain full accessible names/tooltips.

Earlier reports remain diagnostic, with their real failed/preview status intact. They are not reused as final passing acceptance. In particular, `journal-2026-10-14T02-18-53-808Z` contains two real original Moe hospital constitutional-amendment defeats, each completed through its three Continue messages, Liberal ELITE score screen and return to Title. That source fixture can naturally lose during automatic loading. The driver records this exact original outcome and can reimport the unchanged fixture in a fresh isolated context; it never edits the save or bypasses the original ending. The final run reached its populated archive on the first attempt.

## Reproduction and scope

```powershell
& 'C:\Program Files\nodejs\node.exe' scripts/journal_browser_review.mjs --url http://127.0.0.1:18876/ --package-root 'D:\Programming\LiberalCrimeSquad2026\.local\package-qa\journal-022724\LiberalCrimeSquad2026-20261014-022724-dbc3f95b' --stop-server
```

Use the packaged launcher's isolated 18876 origin before running. Final mode rejects keyboard-skip and known-Ledger-bypass flags. Diagnostic `--preview`, `--layout-only`, `--article-only` and `--newgame-only` modes are explicitly labeled preliminary and cannot satisfy the package gate.

This pass covers the documented journal, campaign, persistence, upgrade and offline paths. It is not an exhaustive playthrough of every possible encounter or a certification of every browser/platform. Windows native packaging and the full Dart/source checks have their own release evidence. [The visual review](D:/Programming/LiberalCrimeSquad2026/docs/GANGSTERS_JOURNAL_REVIEW.md) records the original-screen comparison and visual limitations separately.
