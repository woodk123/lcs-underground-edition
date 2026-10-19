# Architecture

The Flutter project is in `upstream/`. Its layout stays close to [New Age](https://github.com/ashley-s-fox/lcs-new-age) so engine changes can be compared with the original project. This is a fork of the Dart game, with a new presentation layer.

## Engine and interface

Completed operations show a source-owned return acknowledgement with newly carried loot, cash received, expenses and injury deltas. Cash is scoped to entry/return; travel, later pawn sales and treatment are not attributed to a raid. Nonzero operation cash is retained in existing squad-result prose, without new save fields. Pawn receipts list actual stock removed and actual sale proceeds separately. Visit readiness reads current weapons, ammunition and per-patient First Aid eligibility without simulating combat or changing orders.

- `upstream/lib/main.dart` starts the original sequential game loop.
- `upstream/lib/engine/` supplies the console, awaited input and structured screen/action metadata.
- `upstream/lib/modern/` contains the journal, dossiers, maps, creation screens and read-only help/calculation views.
- `upstream/lib/basemode/`, `daily/`, `monthly/`, `sitemode/`, `talk/` and `justice/` contain gameplay handlers.
- `upstream/lib/creature/` owns character data, skills, bodies and saved portrait identities.
- `upstream/lib/saveload/` handles persistence, migration, validation and import recovery.

The engine owns campaign state and action availability. UI controls dispatch the current source-authored action and revision through the controllers; labels, painted locations and pixel positions are not command identities. Inspectors and explanations read state without advancing the input loop or making gameplay rolls.

`siteMode` observes entry and completed return through `OperationHistoryCapture`, recording the source handler's actual personal deltas and squad results in optional per-person `operationHistory` snapshots (latest 50). Failed/interrupted readers do not commit history. Existing saves default to empty history; crime totals and news cannot reconstruct personal participation. Wanted counts remain authoritative for current legal status, independent of historical entries and heat. Capture and inspection make no gameplay rolls. Immediate opinion changes are distinct from later news coverage and evidence publication. The optional field retains save compatibility 1.5.6; earlier builds may discard this fork-specific history when resaving.

Orders use a local draft before confirmation. Changing actor discards that draft while retaining the order group, category and map browsing state. Ordinary confirmations keep the same category open for repeated assignments; required follow-up choices stay with their original reader. Confirming must affect the selected actor or squad only. Preserve the original timing, cost and eligibility checks in the gameplay handlers.

The day footer and headquarters command menu stay blocked while a personal order, Network role, selected visit or Bases purchase awaits confirmation. Retained callbacks recheck the live draft before dispatch. Base purchase confirmations also retain their exact action, source revision and local draft version, so cancelled or replaced drafts cannot spend money later.

Required education choices annotate their current source skill actions with the exact person ID. The journal retains that actor and shows an incomplete-choice card while the original skill picker runs; it never treats the picker as an ordinary order frame or borrows an actor from an unrelated report. City maps and the Organisation map expose Queue visit beside the browsed building and squad. This routes through the original destination planner and its exact current action in one operation; browsing stays read-only, no day is advanced, and queued departures remain cancellable. The Operations planner retains its destination review and Enter/Escape controls. Actual on-site visit status is distinct from a queued departure.

The Network tab wraps the original sleeper order readers with a permanent roster, current-role inspector and explicit draft confirmation. The source shares its exact assignment-eligibility reason with this view; unavailable living sleepers remain visible. Monthly standing orders and next-eligible-day recall keep their original processing. Role-review acknowledgements live in local preferences keyed by campaign and person, separate from exported saves. Job, workplace, order or availability changes invite review; ordinary date, infiltration and recovery-countdown changes do not. Keeping a current role is presentation-only.

People is a permanent global directory with Directory, Leadership and Captives scopes. It includes crew outside squads and offers source-routed order, squad, promotion and captive-staffing actions. Profiles retain their original person roster and Back to directory action; the directory's Equipment utility opens the existing equipment reader. Roster tools retain the source sorting/reordering controls. Bases shows safehouses, residents, supplies, facilities and stored equipment, routing investments, home-base assignments and transfers through their original readers. Section IDs remain stable: Network is 8, People 9 and Bases 10; the earlier sections retain IDs 0–7.

`OrganisationReviewStore` records observed returns and finished training in campaign-scoped local preferences. Its first headquarters observation establishes a baseline; it does not invent historical events. Training completion requires a later date, so cancelling an order on the same day does not create a completion notice. New orders and Keep resting acknowledgements clear follow-ups; a returned person rejoining a squad also clears their return notice. These notices add no game-save fields and consume no gameplay RNG.

The People recruitment reader lists actual pending sessions, readiness, contact capacity and venue warnings. It explains that follow-ups run after daily work independently of the recruiter's ordinary assignment. New crew and custody releases also produce observed follow-ups. Review snapshots retain queued squad visits; a later idle snapshot reports that the visit order ended, without claiming travel succeeded. Same-day cancellation remains quiet. The order card explains that visits replace earlier daily assignments rather than suspending them.

Visit follow-ups may retain a supported previous daily job in local review history. Organisation and People can prepare that person's current source-authored job choice again; normal eligibility, draft cancellation and confirmation still apply. Parameterised training, crafting and captive selections are not replayed. No orders resume automatically and no campaign-save fields are added.

Agenda and detailed law guides share read-only victory-condition counts. Bases rent summaries mirror the original collection on advancing from the 3rd, new-lease exemption, landlord sleeper waiver and invalid-lease eviction rules; projections never debit funds or change leases.

Newspaper separates Archive from Production. Production reads current writing/streaming assignments, studio requirements and evidence stocks without consolidating inventory. Assignment callbacks prepare the real actor's order for confirmation in Organisation. Evidence remains a separate original month-end decision: when eligible evidence is held at an LCS-controlled site, the game asks whether to consume one copy for a special edition. The planning view never publishes evidence itself.

Production exposes the accumulated background-influence pool and its monthly resolution, distinguishing daily writing from archived special editions. Both writers and streamers must satisfy the source's active-crew predicate to contribute to a special edition. Publication runs before monthly sleeper work, so newly leaked evidence cannot feed the decision already completed at that boundary. The source choice explains one-copy consumption and declining without adding a second publishing mechanism.

Sleeper reports retain actual payouts, exposure, deliveries and infiltration gains in coherent awaited readers when the movement can see events. Blind time uses the existing log rather than introducing hidden input waits. Equipment theft without a Site workplace is unavailable and old stored orders safely report a no-op. A read-only source projection warns when Uncover Secrets has no matching document source; it never changes rolls or invents loot.

Funding frames identify their reporting period and campaign date. Only the original required report's completed acknowledgement produces a closed-report marker. `MonthlyLedgerHistoryStore` keeps the latest immutable acknowledged snapshot in campaign-scoped local preferences before monthly totals reset; Ledger can revisit it without replaying commands or resetting accounts. Current-month figures still come from the original reader, and loading an older campaign date hides future local history.

The funding reader includes categories with a monthly or daily amount, so resetting monthly totals does not hide the latest processed day's figures. When a source chapter returns to headquarters during a busy day command, the shell retains that pending return until the command completes; required monthly readers remain in control before Organisation resumes.

Profile selection follows the source reader's declared roster and current arrow actions, retaining its page and scroll. Renames, confirmations and event readers block person navigation. Footer and keyboard navigation update the journal selection. Equipment selection is presentation-only: highlighting a person must never dispatch the numbered action that removes their weapon. The active squad remains the original engine's squad.

Travel labels show costs and unmet requirements for the particular route. Free nearby destinations need no general travel warning. Full rules remain available through Order mechanics; displayed notes never override the source planner's action availability or departure checks.

Portraits use a separate deterministic identity calculation. Casting and rendering must not consume the gameplay RNG. Faces, assignment age and cosmetic variants persist in saves; appearance overlays reflect supported equipment and injuries. See [portrait details](PORTRAIT_LIBRARY.md).

Field movement, escape directions, speaker and conversation choices belong to their individual source readers. The source publishes the same availability used by its handler, including ordinary movement past frightened occupants. Retrying a prompt republishes its own actions; it never restores actions from an earlier reader. Field callbacks retain the action object and console revision. Read-only field dossiers keep the map in place and block both pointer and keyboard commands beneath them.

While a door reader targets the attempted tile, `doorInteractionOrigin` retains the standing position for tactical presentation. It is cleared together with restoring engine coordinates in `finally`, is not saved, and makes no gameplay rolls. Failed safe attempts retain their fixture and original notice checks; rewards and fixture removal require a successful opening. Bulk pawn confirmations publish only their current Yes/No source actions.

The browser clips the outer Flutter view without making it a scroll container. Accessible focus navigation can scroll the game's inner readers, but must not move the canvas or cut off the journal tabs.

Hospital admission, discharge and court defense publish `RecoveryContext` snapshots in `engine/recovery_context.dart`. The journal reuses those people, text, costs, skill values and exact action objects; healing, billing, custody and verdicts remain in their original handlers. Full charges and medical mechanics are available on demand. Discharged patients return to their base without automatically rejoining a squad, and leaving a bill unpaid retains the debt.

Daily professional-treatment warnings clear the departing reader before authoring their notice. A field screen's body boundary must not hide the warning or leave the engine waiting without a current Continue action.

On-foot and car pursuits publish `PursuitContext` snapshots in `engine/pursuit_context.dart`. They expose only crew, road conditions, vehicle gaps and encounter information already printed by the current source reader. The pursuit journal retains action identity/revision checks across retries and nested status/equipment readers; its dossier is a read-only modal. Obstacle controls retain their current source meanings, including F for slowing down. Street arrests still come from the original daily activity checks and surrender handler.

Car road animation is cosmetic. It repaints its captured console only while the car reader awaits input, without consuming campaign RNG, changing command revisions or contributing glyphs to authored reports. Nested readers own the console while open. The chase stops and awaits animation cleanup on every exit; driving, combat, obstacles and capture remain in the original handlers.

Siege responses stay in the headquarters journal with the squad leader rail on the left. The original headquarters reader publishes an immutable `SiegeBriefing` and its exact F/G/W capabilities in `HeadquartersFrame`. The journal shows the current attack, consequences and responses; supply/security detail expands on demand. Responses retain their source action and revision, and inspection blocks battle/surrender keys. The source passes the displayed site into its response initializer and forms defense from people physically there, preserving other squads and hospital patients.

Operation cleanup snapshots participants before custody, hauling or relocation changes their membership. Stabilization and prison-escape flag cleanup apply to that roster, including hauled people and local siege reserves. People at other sites keep their condition. Defeated solo pursuits, uncarried casualties, reserve promotion and fatal car crashes clear dead actors' reverse squad membership when removing them. Living hauled people retain their in-operation ownership. Police siege confiscation reports use one authored acknowledgement reader so Continue remains available.

Free Clinic patients remain admitted until the existing healed/60-day discharge condition. Clinic support remains 6 at an ordinary non-LCS site and generates no new treatment bill; university hospitals retain support 16 and law-dependent charges. Sleeper staff at their own clinic workplace are distinguished from admitted patients.

## Development

Use a full restart after engine changes; hot reload cannot reliably restart an awaited game loop. Add meaningful regressions under `upstream/test/` when changing rules, persistence or command routing. Build and release tools live in `scripts/`; generated reports, SDKs and packages are ignored.

See [building](BUILDING.md), [testing](TESTING.md), [assets](ASSETS.md) and [changes](ORIGINAL_CODE_CHANGES.md).
