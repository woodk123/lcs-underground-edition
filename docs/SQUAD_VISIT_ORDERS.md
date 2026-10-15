# Squad visit orders — 14 October 2026

Squad visits now use the journal order workflow. Orders → Operations includes **Visit a location**, which opens the original destination planner. Selecting a building remains read-only; **Prepare visit** on the left job card opens that same planner at the selected building, including original pagination. There is no separate large visit button beneath the map and no additional dialog.

The prepared card says **Visit [location]**, identifies a **Squad order**, and includes the current members, destination, calculated travel cost, requirements, next-day execution and precedence over individual daily tasks. The existing bounded mechanics area holds long member/requirement descriptions; cost and execution timing lead, while Confirm order and Cancel remain pinned at 150% text. Confirmation queues the destination; the queued card says to advance the day to travel.

## Source review

Only `upstream/lib/modern/organisation_journal.dart` changes implementation. The controller, city-plan component, original `basemode/plan_site_visit.dart`, and daily travel/simulation handlers remain unchanged. Preparation navigates original source-authored district/site and PageUp/PageDown actions. Confirmation uses the current enabled site action and current revision through `OrganisationController.sendAction`. UI code writes no campaign fields, ledger values, dates or RNG state and adds no eligibility/cost calculations. Cost comes from the existing activity-calculation descriptor.

Cancellation uses the existing source-authored U+E000 safe section exit through `returnToHeadquarters`, preserving queued squad/personal orders. Journal Escape/X/Space also use that safe exit; destination letter keys prepare the card and Enter confirms it. Classic retains the original immediate inputs and original manual Cancel semantics. The original destructive city-root Cancel is not advertised as journal cancellation. Printed party-selection actions are omitted from map navigation; actual source pagination and Back one step remain available.

Strict fidelity pins the reviewed journal contents to `16b67543a62480010227cabd28215aa98d5aa5be9b4697fbf99ae2084d13e8be`. All other pins pass unchanged: 355 audited files, 200 original Dart files retained, 171 unchanged and 29 previously reviewed changes. No original simulation changes were introduced in this update.

## Verification

- **438 full Flutter tests pass**, including seven visit tests. Full analysis reports **No issues found**.
- Both entry routes prepare/cancel through the original awaited planner; complete campaign JSON and seeded RNG sequences remain unchanged. Prior squad and personal orders survive cancellation. Confirmation changes only the original squad destination assignment.
- Source-disabled closed sites can be inspected with Confirm disabled. A target beyond the original eleven-item page is located using real planner pagination. Destination keyboard input prepares rather than commits; Escape/X/Space preserve the old queue.
- Fresh release web build and offline manifest completed. The existing server continues serving `upstream/build/web`; it was not stopped. Runtime SHA-256: `541d126ae153ee20ded46753bf82227fed00c5f6a18782c52c071b646c3b8bab`. Worker version: `f5746b77`.
- Isolated Chrome profile: **28 passed checkpoints**, no page/console/network errors. Complete actual save exports compare equal after building-route and Operations-route preparation/cancellation. Confirmation followed by real next-day advance reaches the original al-Shamie Park arrival notice and playable field operation, then returns to HQ.
- Captures were visually inspected at **1280×720 and 800×600 with 150% text**, including the common prepared card and pinned controls. Long details use the card's existing scroll area.

Browser evidence: [squad-orders-2026-10-14T11-26-34-144Z](../reports/browser/squad-orders-2026-10-14T11-26-34-144Z/report.json). Reproduce with `node scripts/squad_orders_chrome_review.mjs --expected-hash 541d126ae153ee20ded46753bf82227fed00c5f6a18782c52c071b646c3b8bab`. Test/analysis/build logs are in `.local/reports/squad-orders-*.log`.

Separate build record: [`release/SQUAD_VISIT_ORDERS-20261014.json`](../release/SQUAD_VISIT_ORDERS-20261014.json), also referenced by `release/DELIVERY.json.current_live_update`. Previous live-update records and immutable release archives remain historical. The user's active browser campaign was not accessed; no new native build or exhaustive simulation playthrough is claimed.
