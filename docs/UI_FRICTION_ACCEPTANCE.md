# UI friction and space acceptance

Accepted runtime: `1aa0be78906b3f97a0ef3cc8cbebb983ca15edb234ecb9c0da9da16b5ea2b82a`. Offline worker: `3db5f6fd`. Acceptance completed 2026-10-13 UTC / 2026-10-14 UK time, using headless Microsoft Edge 155.0.4283.45 and ordinary browser accessibility controls. No game-state injection or native desktop automation was used.

## Result and evidence

The [complete browser report](../reports/browser/smoke-2026-10-13T23-36-30-298Z/report.json) passes **87 checkpoints**, with **zero skipped checks, page errors, console errors or failed requests**. It exercised the candidate package through its own launcher on isolated port 18876 and verified that the package JavaScript matches the accepted runtime. The player's port 8765 server and browser profile were preserved.

The same report directory contains:

- [Existing campaign review](../reports/browser/smoke-2026-10-13T23-36-30-298Z/existing-campaign/report.json): **25 passed checkpoints and 25 screenshots**, using the unchanged five-person `felix_1_0.json` campaign at 1600×1000, 1280×720 and 800×700. Its original report/video remain under `reports/city-review-2026-10-13T23-35-58.489Z/`.
- [Save-preserving upgrade](../reports/browser/smoke-2026-10-13T23-36-30-298Z/upgrade/report.json): **7 screenshots**, unchanged QA Founder campaign on January 4, 2023 with $1004 and Laying Low, and the new runtime verified inside the actual service-worker cache.
- `city-animation/`: 24 actual browser frame captures and a WebM, 8 distinct rendered scene states from the generated eight-frame atlas, and **zero changed pixels** between reduced-motion captures.

## Interaction findings

Routine sections can be reached directly from nested assignment and other explicitly navigable menus. One click from a task screen opens Media; returning to assignments preserves the actual task. Opening Operations and switching to Media preserves the exact queued destination, date and funds; the separate original Cancel Departure command still cancels it.

Everyday crew inspection opens alongside the current screen. Navigation and city/list controls remain usable while inspection is open, and primary HQ quick actions clear that local inspector without an extra dismissal. The optional full dossier retains its detailed skills and campaign record. Inspection, resizing and decorative animation preserve campaign date, funds and orders.

HQ shows all five imported crew on the first screen at 1280×720 and 1600×1000. The topbar keeps date and funds visible at 800×700. Activity screens show the actor, blood, selected assignment, relevant factors, costs, risks and timing; original equipment/attribute/skill details expand in place. Done remains visible near the actor. Copy states that task selection applies immediately and processing occurs when the day advances.

City/district objects open their next list with one activation. Actual sites keep an explicit Queue squad visit action, with execution timing explained before committing. Every exposed fitted city object and the inspected building's order control stays inside the reviewed viewports. Map and list modes remain available during crew inspection. No unrecorded site security, heat values or success probabilities were invented.

Specialized screens have visible exits: the actual imported KILLER FOOD article opens, retains its recorded +12.8% impact and accessible exact value, then returns to its archive through Continue. The full tactical map opens, zooms, fits and returns through Back to operation. These controls dispatch the existing any-key input.

## Gameplay and persistence checks

The 87-checkpoint run covers keyboard Tab/Enter, naming, fundraising assignment and a real day advance, people/squads, agenda, Media, city planning, original order cancellation, save export/import, malformed-import rejection preserving a valid campaign, complete browser-process restart, 125% reading size, guide dismissal, a real public-site visit, tactical pointer and keyboard movement, map/equipment/ammo controls, site exit and campaign recovery.

The test stopped only its isolated packaged server, reloaded offline, resumed the campaign, advanced a day, saved and reloaded again. The cache contained 116 application resources. The fresh campaign's archive happened to contain no selectable story; the separate prior-profile upgrade provides the actual article and pointer-return evidence instead.

## Scope and remaining limits

Selected rendered screenshots were inspected directly. Lower utility actions may require ordinary vertical scrolling on short/narrow screens; the primary Done and building order controls remain visible in the tested states. Dense district labels can be enlarged with map zoom or read in Locations list.

This certifies the documented browser scenarios, not every late-game branch, sleeper configuration or tactical encounter. Exact menu-navigation/state/RNG invariants and activity identity/mechanics have separate source tests; 225 source tests and clean analysis are documented in the release build evidence. Warm headless frame-delivery observations are not physical-GPU or large-campaign benchmarks. Native Windows compilation is recorded separately; native graphical playthrough is not certified by this review.
