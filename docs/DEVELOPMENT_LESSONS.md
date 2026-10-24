# Development lessons

Reuse the original gameplay handlers, test complete interactions early, and keep builds traceable. Recurring follow-up fixes have involved navigation, retained UI state, hidden choices and misleading explanations. Faster development depends on catching those problems before rebuilding and reviewing a whole player.

These practices combine the locally available project sessions of 13–18 October 2026 with repository maintenance checked on 24 October. Detailed commands remain in [Building](BUILDING.md), [Testing](TESTING.md), [Architecture](ARCHITECTURE.md), [Assets](ASSETS.md) and [Versioning](VERSIONING.md).

## Recurring problems and what to do

| Lesson | Evidence from development | Practice to retain |
|---|---|---|
| Test navigation with existing state. | Recruitment's grey-panel crash appeared after scrolling: an expansion flag collided with a saved scroll offset. Broad tests had passed before the actual path reproduced it. | Give stored UI state distinct identities. Test scroll → open → close → revisit in one application lifetime, including switches between people and sections. |
| Keep the current engine reader in charge. | Stale field actions reached later prompts; car animation invalidated clicks and consumed gameplay randomness. | Dispatch the current source-authored action with its person ID and revision. Keep inspection and cosmetic animation independent of input, campaign state and gameplay RNG. |
| Preserve one clear confirmation flow. | Visits initially competed with the normal job card; current Network orders could look like new changes; duplicate Lay Low controls confused the choice. | Use the shared prepare/confirm/cancel pattern for pointer previews. Physical game keys retain the original Classic reader timing and Back hierarchy; never add a confirmation or substitute a preview command for a source key. Distinguish browsing, a draft, the current order and a confirmed departure. Keeping the current order must clear a pending change. |
| Keep progress and return controls predictable. | Reports, announcements, defeat and surrender paths sometimes hid or lost their Continue action. Pointer barriers also left keyboard commands reachable underneath inspectors. | Keep the current source Continue/Back/decision reachable. Block underlying pointer, focus activation and shortcuts during modal inspection. Never substitute Advance day for a required acknowledgement. |
| Show the information needed for the decision. | A hospitalized crew member looked missing; available shelters looked like eight owned bases; recruitment meeting difficulty looked like persuasion difficulty. | Show status, location, scope, timing and relevant costs beside the choice. Keep important values beside their names, with detailed formulas available on demand. |
| Derive explanations from the actual rules. | Law descriptions initially overstated direct effects; equipment, injury, recruitment and Juice help required checking their handlers. | Trace the real calculation and eligibility conditions. Label estimates and conditional probabilities. Distinguish political/story effects from direct mechanics; previews must not make game rolls. |
| Verify what is actually delivered. | Cross-platform line endings broke a pinned asset hash; removing an apparently unused icon dependency broke font output; license validation initially checked the retained copy instead of the packaged copy. | Check built assets and extracted packages, including their actual licenses, hashes and source identity. Import searches and successful compilation provide only part of the evidence. |
| Wait for the state being asserted. | Founder semantics changed before portrait pixels painted; an async offline-activation predicate returned a Promise before the worker finished. | Await asynchronous lookup before polling a synchronous readiness predicate. Require the selected image or complete cache, with a bounded deadline and the original assertions intact. |
| Preserve native focus semantics when changing control labels. | Equipment's clickable Cancel had no browser focusability metadata when the entire native button was excluded from semantics. | Exclude only visual label contents when supplying an accessible name. Retain the button's native action/focus semantics and verify actual Tab → Enter activation in the compiled journey. |
| Capture failures before cleanup. | A fresh profile showed only a processing shell while foreground and service-worker XML requests were pending; the page reported no network failure. | Retain the raw source stage, pending requests, worker state and loaded-build identity before closing the profile. Keep each attempt's evidence separately. |
| Recover a failed transfer before parsing. | An injected foreground XML timeout left startup permanently processing even though the worker downloaded the same asset. Flutter's string cache retained the rejected future. | Retry only the failed asset read with a bounded delay and evict that key's failed future. Keep parsing outside recovery so earlier XML/maps, campaign state and RNG are never replayed. Successful churn tests establish a non-reproduction, not the historical transport trigger. |

The implementation contracts are described in [Architecture](ARCHITECTURE.md#engine-and-interface). Useful regressions include [page storage isolation](../upstream/test/page_storage_isolation_test.dart), [action identity](../upstream/test/action_identity_test.dart), [organisation journeys](../upstream/test/organisation_journal_test.dart) and [tactical shell acceptance](../upstream/test/tactical_shell_acceptance_test.dart).

## A fast working loop

1. **Establish the starting state.** Inspect Git status and the affected source handlers, then read the relevant guide. Use the [source ownership map](ARCHITECTURE.md#find-the-owner-of-a-change) to find the boundary, and `python scripts/developer_doctor.py` to diagnose missing prerequisites without starting a build. Record existing changes before editing. Identify the player-visible problem, how to reproduce it and the files the task owns.
2. **Define the expected interaction.** Name the actor, current reader, starting state, action and expected result. For inspection or cancellation, state what must remain unchanged. For a consequential action, check money, inventory, membership, date and persistence as applicable.
3. **Make the smallest coherent change.** Reuse source actions and existing presentation components. Keep gameplay fixes distinct from presentation changes so each can be explained and reviewed. Add a regression that fails for the actual defect when rules, saves or routing are involved.
4. **Get focused feedback first.** Use the [focused-check mapping](TESTING.md#choose-focused-checks) to select existing tests for the changed boundary, then run the relevant tests and analysis while iterating. Use the pinned SDK; regenerate serializers after changing saved fields or JSON annotations. Fully restart after engine changes because hot reload cannot restart an awaited game loop reliably.
5. **Verify the integrated result.** Once the change settles, run the broader checks appropriate to its reach. Review the affected journey in the final compiled build when browser/native behaviour matters. Repeat checks when source changes, a failure appears or coverage remains uncertain; unchanged passing checks need not be repeated without a reason.
6. **Leave a clear handoff.** Report the outcome, changed files, checks, exact source/build identity, artifact or playable URL, and remaining gaps. Follow [Versioning](VERSIONING.md) for player-facing notes. If committing, stage an explicit path allowlist and inspect the index and remaining working tree.

For small wording or documentation changes, keep verification proportionate. A full player build is not needed to establish that a documentation link resolves. Release preparation still requires the existing release gates.

Where work is delegated, agree file ownership and shared interfaces first, with one owner coordinating integration and the final build. Parallel edits, builds and QA servers share resources unless explicitly isolated. Review the integrated source after changes settle, then rebuild and identify the accepted artifact; separate passing reports from different builds do not establish one accepted player.

## Choose checks by the failure being prevented

| Change | Focused verification | Integration evidence |
|---|---|---|
| UI layout or explanation | Check the relevant source facts and widget behaviour. Exercise mouse, keyboard and touch alternatives where affected. | Review the changed flow at desktop and 1024×720 with 150% reading size; treat smaller/mobile layouts as optional robustness checks, not supported targets. Important controls should be usable on entry. |
| Orders, menus or awaited input | Exercise the actual reader, actor identity, cancellation, replacement and retained callbacks. | Switch people/sections, open help, return and confirm. Verify only the intended action occurs and no command reaches a later prompt. |
| Inspection, previews or animation | Compare complete campaign state, pending input and gameplay RNG before/after. | Navigate several related screens in one application/cache lifetime, with an overlay open and keyboard focus deliberately exercised. |
| Gameplay, persistence or versioning | Test the actual handler and meaningful outcomes; regenerate saved-model code when needed. Follow the [version/save checks](VERSIONING.md#save-compatibility). | Load older fixtures, round-trip/export/import and restart. Use declared prepared scenarios for rare branches and ordinary play for natural progression. |
| Artwork, dependencies or compression | Run the asset verifier and relevant native-codec/render tests. Compare the original masters and runtime output. | Inspect art at its actual display size, with transparency and overlays. Visit multiple screens with shared image caches; build the affected player after dependency removal. |
| CI, caching or packaging | Run the affected tooling tests, including stale/missing/tampered inputs and cache invalidation. | Require matching source/toolchain evidence, complete shard coverage and extracted-package verification. Native compilation and native GUI acceptance remain separate checks. |

Test counts describe the executed suite, not the breadth of game outcomes. A rendered fixture proves something different from a browser journey, a native playthrough or an earned campaign event. State which was exercised. Define acceptance criteria instead of treating a “10/10” rating as proof of completeness.

## Build speed and performance

The 17 October build-speed sessions recorded complete nightly publication falling from **17m25s to 3m26s**, about 80% less elapsed time. These were successive runs, not a controlled benchmark or a promise for current builds. Runner queueing and cache warmth varied; one comparison improved queue time by 50 seconds alone. Parallelism also increased the combined runner time for an individual push, even while reducing elapsed time.

The current [CI workflow](../.github/workflows/ci.yml) already runs four test shards on each operating system, independent Windows/Linux/web builds, target-specific SDK caches and verified artifact reuse. [Building](BUILDING.md#checks-on-pushes-and-pull-requests) explains the cache boundaries and how to refresh measured shard weights.

- Measure queue time, the slowest parallel job, publication time and total runner work separately. Speeding up a shorter parallel job may not reduce the wait at all.
- Cache reusable tools and compiler seeds while still generating current serializers and executing current tests. A warm cache must detect an intentionally failing test and a changed saved model. Never use a cached passing status as validation.
- Reuse checked artifacts only when their source, toolchain and payload evidence match. Preserve the independent native Windows build and tests when moving packaging to Linux.
- Stop when a proposed saving is smaller than its maintenance cost. Revisit the pipeline when measured waits start blocking development or the slowest job changes. The sessions reached diminishing returns after the major restructuring.
- Measure player performance separately. Download size, startup latency, memory use and frame responsiveness are different problems. Do not evict useful caches or change loading behaviour solely because a theoretical saving exists.

Artwork was the major download-size contributor. [The quality-90 measurements](BUILDING.md#quality-90-size-measurements-17-october-2026) document real rebuilt ZIP reductions, alongside their scope. Keep PNG masters and provenance, encode runtime images from those masters, and review at game scale before changing quality. Avoid repeated lossy recompression and avoid raising a size budget without reviewing its contents.

The [development-MCP cache](DEV_MCP.md#setup) can reuse a compiled player after a documentation or helper commit when full compile inputs and payloads still match. It retains the original compiled revision and records the currently checked revision separately. Release and CI artifact reuse retain their own commit-identity requirements.

## Keep playtesting reproducible

Use the [existing browser helpers](TESTING.md#browser-regressions) with disposable fixtures, isolated profiles and a separate ignored output directory. Assign an unused QA port and record its owner, web root and compiled JavaScript hash. Several helpers use fixed ports, so check their requirements before running them together. Stop only the server belonging to the task.

Verify the launcher health response and the exact served build. An HTTP 200 or a screenshot of an older tab does not establish which code ran. Inject the offline manifest into the final web output and test offline updates when that path changes. For player-facing launch requests, return the working URL and retain the exact browser origin needed for existing saves.

Cover fresh creation and an opening week as well as established campaigns. Check background rewards, first recruitment, assignments, day advancement, finding absent crew and save/reload. Continue into month-end or a consequential branch when affected. Prepared injuries, equipment, laws or encounters are useful fixtures; record what was supplied and what the player actually earned.

Keep generated logs, captures and timing data under ignored `.local/` or `reports/`. Preserve source art, prompts, manifests, licenses, save fixtures and evidence needed to reproduce a release. Audit references and retention needs before deleting old profiles or packages. Keep durable guides concise; dated test totals and one-off acceptance diaries belong with their run evidence.

## Follow-up improvements worth prioritising

The shared acceptance runner now implements the common journey. Keep further additions tied to actual gaps and repeated setup costs.

1. **Keep the shared acceptance journey current.** Run `python scripts/shared_acceptance.py` for the [common interaction checks](TESTING.md#shared-acceptance-journey). It combines existing focused tests and browser helpers, continues a newly created founder through an actual week, and retains separate prepared recruitment and personnel scenarios. Preserve scroll/revisit, modal keyboard isolation and current-order checks as new chapters are added.
2. **Extend the shared entry point when it saves repeated setup.** The runner already owns isolated servers, identifies the build and collects results. Add another helper only when its coverage belongs in the common journey, preserving its declared fixture and origin requirements. Measure setup friction before building a larger framework.
3. **Track recurring failures and the slowest checks.** Record the reproducing journey, source/build, root cause and regression location. Use those records to choose the next fix or test improvement; refresh timing weights from real reports rather than continually adding workers or caches.

The next development priority should be reliable player journeys and clearer decisions. Further build-speed or runtime optimisation should follow a measured bottleneck.
