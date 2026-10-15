# Month playtest and crafting correction

Acceptance: 14 October 2026. Runtime `b112e17ceda6bef00a50207e4bd3f5dfae4833d6dc3345208a871c1159c9df0b`; offline worker `d97ed72a`.

The isolated real Chrome campaign played **31 consecutive days, 4 January to 4 February 2023**. Every date advanced exactly once; all original crew IDs remained and every member aged once per elapsed day. Each daily balance reconciled with starting cash plus recorded income minus recorded expenses. There were **32 exported/reloaded browser saves**, including a full browser refresh on day 14. Player browser profiles and the active campaign were not used or changed.

The UI journey assigns donations, art sales, live music and clothing sales, changes orders during the month, queues a public Park visit, continues arrival, opens tactical/full-floor maps, leaves the mission and returns to HQ. Community service runs later in the month. Ledger, Justice, Agenda, Newspaper and Reports are inspected weekly. Actual February 1 legislative votes and the required funding report are acknowledged before normal planning resumes. The final cash balance is **$186**; it agrees with the saved ledger rather than a fixed random-income expectation.

The final browser report passes **56 checkpoints**, records zero page/console/request errors, and includes daily exports and screenshots: [report](../reports/browser/month-playtest-2026-10-14T10-24-56-266Z/report.json). Reproduce against the freshly served runtime:

```powershell
node scripts/month_playtest.mjs --expected-hash b112e17ceda6bef00a50207e4bd3f5dfae4833d6dc3345208a871c1159c9df0b
```

## Confirmed bug fixed

Both clothing and flag crafting previously consumed one recycled cloth unit before checking whether the discounted supply payment was affordable. A $4 balance for $5 clothing, or $6 for a $7 flag, rejected the job but lost cloth. Single items disappeared and three-item stacks fell to two.

The handlers now calculate the same discount, reject insufficient funds, then pay and consume the cloth. Existing affordable costs, skill rolls, XP, item output and activity retry/clear behavior are retained. Four regressions failed before the fix and now pass. Two affordable-attempt regressions match exact original output and the following six random draws. [Engine rationale and logs](../reports/engine/month-acceptance-20261014.md).

An independent engine run covers 31 days using original assignment handlers, free practice, paid classes, teaching, clothing/flag crafting, community service and Guardian writing, with eight actual Save & Exit/reloads. It checks funding-report navigation guards and monthly category resets in addition to every date, crew and cash balance.

## Two feedback bugs fixed

Required `showMessage` announcements originally appeared beneath stale headquarters and party rows. Continue could dismiss a message that was below the visible area, and old cash/date text competed with the current footer. The journal now displays the full current announcement first, with the same single original acknowledgement. Classic buffer output remains unchanged. Eight metadata tests verify text, buffer/colors/actions, input timing, lifecycle cleanup, campaign state and RNG.

Congress displays President, House and Senate at fixed source columns 35, 62 and 70. Generic paragraph reflow collapsed empty President cells, visually putting chamber counts under the wrong heading. The journal now reads those exact printed slots into per-bill cards with explicit branch labels. Blank published slots display Pending; future votes/outcomes are not predicted. Original bill colors and acknowledgement keys remain. Four view tests verify notice priority and vote identity at 1280×720 and 800×600 with 150% text; the required-reader footer also fits. Final arrival, Congress and President/Veto captures were independently inspected and both findings are resolved.

## Final verification

- 436 full Flutter tests pass; full analysis reports no issues.
- Strict source fidelity passes 355 files: all 200 original Dart files retained, 171 unchanged and 29 explicitly reviewed. The two newly reviewed originals contain only this documented crafting correction; authored data and save schemas are unchanged.
- Fresh web and Windows release builds compile. Native graphical play remains outside this browser/engine review.
- Earlier immutable ZIPs and their recorded acceptance remain unchanged; the corrected build is served locally and recorded in `release/DELIVERY.json.current_live_update`.

This covers a month of the exercised campaign and the targeted affordability failures; it does not claim every possible combat, crime, arrest or campaign-ending branch has been played.

## Subsequent squad-order UI build

The later [squad visit order review](SQUAD_VISIT_ORDERS.md) records a new served web build separately. It exercises unified visit preparation/cancellation, prior-order/RNG preservation, original confirmation and actual next-day park arrival. It changes presentation only and does not replace or relabel the historical month-playtest runtime, exports or results above.
