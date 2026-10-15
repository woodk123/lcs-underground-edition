# Liberal Crime Squad modernization — delivery plan

Plan prepared 13 October 2026. This document describes the intended product and its acceptance gates. It is not a completion report. Actual evidence belongs in dated verification reports.

## Product commitment and scope

Build a local, offline, single-player game that makes Liberal Crime Squad readable and approachable while retaining its strategic, character and tactical depth. Modernization changes presentation and interaction; it must not quietly replace the original game with a short scenario, clicker or a few abstract mission rolls.

The integration lead's initial source audit found approximately 200 Dart files and 62,475 lines in the upstream Flutter game, including the complete gameplay engine. This is a strong reason to use the user's exception to the Godot preference: keep that engine and modernize its Flutter presentation. A new Godot implementation would recreate a large rules/content surface and risk quietly losing depth. Godot tooling remains a useful workflow reference, rather than a new runtime dependency.

The selected approach works inside the cloned `upstream/` Flutter project. Capture semantic options and screen flushes at the existing console boundary; render a bespoke title/HQ and clearer structured screen presentation while retaining a fully usable console-compatible path for tactical and less common screens. The retained engine remains authoritative. Test that presentation capture cannot reorder commands, swallow input or change time/RNG/state.

The upstream checkout is the behavioral and content reference. Record the exact upstream revision, preserve its license and attribution, and inventory its systems before treating any feature list as complete. The upstream-research owner supplies that inventory; the lists below are acceptance categories to reconcile against it, not a claim of a finished port.

The full-game target includes:

- Character creation, persistent attributes and skills, ideology, health, equipment and relationships.
- Recruiting, persuasion, squad organization, bases, daily assignments, training, income and resource management.
- City/location navigation and tactical site operations with meaningful movement, encounters, detection, combat, injuries, loot, retreat and consequences.
- Political advocacy, media and public opinion, laws, elections and the broader simulation that gives missions their purpose.
- Crime and law-enforcement consequences, including the upstream's relevant investigation, arrest, trial, custody and siege systems.
- Long campaigns, progression, setbacks, victory and defeat; saves must preserve the active campaign and tactical state where the game allows saving.
- The upstream's equipment, creatures, sites, encounters and authored event content, or explicitly documented equivalents justified by the source audit.

If a smaller first playable is delivered during development, label it as an alpha or vertical slice and enumerate its missing systems. It cannot satisfy the full-game production acceptance gate merely because it launches and its included loop is polished.

## Work ownership and integration

| Role | Responsibility | Integration artifact |
| --- | --- | --- |
| Project manager | Priorities, scope accounting, dependencies, milestone evidence and release gates | This plan and milestone review notes |
| Upstream researcher / integration lead | Source audit, licensing, architecture, gameplay fidelity, integration and packaged build | Source/system map, architecture, final validation report |
| Programmer | Engine/presentation boundary, modern widgets, persistence regression and meaningful tests | Runnable game and reproducible checks |
| Image generation agent | Consistent production bitmap art, asset organization, import contract and provenance | Asset manifest, generation prompts and inspected artwork |
| UX and visual designer | Information architecture, readable layouts, action feedback, onboarding and interaction review | Shared UI specification and capture review |

Keep ownership boundaries explicit. The retained game engine is the authoritative campaign state. UI reads it and dispatches existing validated commands. Screens must not maintain independent copies of cash, squads, world state or tactical outcomes. Generated images provide atmosphere and illustrative identity; all text, statistics, selection states and input stay as real Flutter widgets. Semantic rendering must preserve the original command identity rather than guessing it from the visible label.

Integrate in runnable increments. Each feature change includes behavior, interface, failure feedback and the appropriate verification. Never leave a visible button that silently does nothing. An unavailable action explains its prerequisite or reason.

## Reusable RacingDynasty workflows

Inspected read-only: `D:\Programming\RacingDynasty\AGENTS.md`, `docs/DEVELOPMENT.md`, `docs/ARCHITECTURE.md`, `docs/VISUAL_QA.md`, `docs/UI_DESIGN.md`, `tools/dev.py`, `tools/godot-ai.json`, `tools/race_2_5d/toolchain.json`, `export_presets.cfg`, `scripts/tests/run_all.gd` and the save boundary.

### Toolchain

- Its actual standard GDScript engine is available at `D:\Programming\RacingDynasty\.local\race-2-5d\godot\godot_console.exe`. Running `--version` on 13 October 2026 returned `4.7.2.stable.official.ed1daf0bf`. The graphical sibling `godot.exe` exists.
- RacingDynasty pins the engine version and archive SHA-512 and uses a small Python launcher that resolves paths from the checkout rather than relying on PATH. Reuse that practice for the local Flutter/Dart SDK and LCS-owned launch/build scripts; avoid coupling the shipped game to the other repository's path. The integration lead is provisioning `.tools/flutter`.
- Matching Godot 4.7.2 export templates were not present in the standard local template directory during this inventory. `%APPDATA%\Godot\export_templates` contained only `4.6.2.stable`. Install and verify matching templates before claiming a standard 4.7.2 release export.
- RacingDynasty pins optional `hi-godot/godot-ai` tooling to 4.1.0 and verifies the exact project path, plugin/server/engine versions and readiness before editor operations. The equivalent discipline applies to the correct Flutter project, SDK version and target device here. Do not attach to RacingDynasty or install Godot MCP for a Flutter build. Editor integration is development-only; play and release builds require neither MCP nor an API key.
- Keep `.godot`, `.local`, exports, capture evidence and source-art experiments out of inappropriate imports and shipping resources. Keep addon helpers out of exported autoloads.

### Architecture conventions worth adapting

- Keep domain rules separate from rendering. RacingDynasty's simulation has no scene tree dependency and reproduces results from seed and commands. LCS retains its existing Dart rules; a widget rebuild must never rerun a gameplay decision.
- Use one campaign state owner. Preserve the upstream's state/command lifecycle and keep transient selection/layout state in the presentation layer. UI refresh never advances the campaign clock.
- Split production artwork, UI components and gameplay code into navigable directories. Put shared styling in Flutter's theme and reusable widgets, and use constraints/responsive layout rather than screenshot coordinates.
- Use Flutter actions/shortcuts and preserve the upstream command bindings. Keyboard focus, selection and disabled states must remain visible. Pointer and keyboard input dispatch the same engine action.
- Audit and retain the upstream save schema. Any changes need explicit versioning/migration, validation before installing loaded state, and temporary-file/backup behavior where the storage platform supports it. Keep fixture saves separate from player saves.
- Verify APIs against the actual pinned SDK. RacingDynasty explicitly records that a structurally valid GodotPrompter example previously contained an invalid API; guidance and structural checks are not proof that code compiles.

### Verification

- First resolve dependencies and run Flutter/Dart analysis; then focused unit/widget tests; then campaign/tactical integration. Broaden a passing suite when new changes or failures warrant it rather than repeating unchanged checks without purpose.
- Aggregate real test exit codes and name explicit skips. Capture stdout/stderr and distinguish compile/analyzer errors from test failures. A semantic-option fixture should prove identity, enabled state, order and dispatch of original engine commands.
- Use deterministic graphical fixtures at known campaign states, isolated save paths and fixed viewport sizes. Inspect actual PNG pixels for clipping, contrast, focus, empty states and long content. Headless success does not prove UI quality.
- Record the revision, date, command, exit status, renderer, resolution and skipped checks for each verification run. Historical screenshots and logs establish only the run that created them.
- Smoke-test the actual package: first launch, new campaign, onboarding, a complete tactical operation, return to the base, save, quit, reopen, reload and continue. Verify offline operation and error-free logs.

RacingDynasty's horse art, racing-green palette, Forward+ requirement and race-specific test fixtures are not inherited product requirements. LCS chooses the renderer and visual language that fit its own presentation; a 2D Control-driven interface does not need the racing game's 3D lighting stack.

## Prioritized milestones

| Milestone | Deliverable | Gate to advance |
| --- | --- | --- |
| 0 — Evidence and foundation | Exact upstream revision/license; source-system inventory; pinned Flutter/Dart SDK; runnable original; art/UX direction | Dependency resolution, analysis and original launch; system map identifies behaviors/content; presentation seam leaves the retained engine authoritative |
| 1 — Presentation bridge and first campaign loop | Semantic options/flush capture, modern title/HQ, preserved complete console path, onboarding, feedback, save/reload | Human-readable first-session path works through original game rules; pointer/keyboard dispatch identity is tested; no dead controls, lost commands or false success feedback |
| 2 — Strategic presentation | Recruiting, squads, equipment/economy, assignments and world/news navigation rendered clearly | Upstream feature matrix maps each management path to modern view or fully functional compatibility view; long campaigns preserve original invariants |
| 3 — Tactical presentation and consequences | Readable tactical map/text, original actions, encounter/combat/escape feedback, result and legal/enforcement navigation | Multiple site types, squad sizes and approaches work through the retained engine; failure paths remain usable; post-mission state is applied once |
| 4 — Campaign usability completeness | Remaining audited screens/content accessible; victory/defeat routes; retained saves verified; coherent tutorial/help and accessibility | No essential upstream loop is hidden or inaccessible; compatibility views have adequate navigation/readability; campaign can reach victory and defeat with reproducible saves |
| 5 — Release candidate | Polished consistent art, audio/feedback, readable responsive UI, supported platform package and player guide | All production gates below pass against the exact packaged revision; open defects are triaged and no release blocker remains |

Milestones 2 and 3 may progress in parallel after the semantic presentation/command contract exists. Art and UX work begin at milestone 0 and review every integrated screen; they are not a final coating. Prioritize existing engine fidelity and complete navigability before expanding bespoke screens: unchanged engine → faithful command capture → campaign loop → tactical loop → consequences → presentation breadth → release verification.

## Production acceptance gates

### Gameplay fidelity and completeness

Maintain a traceable matrix of upstream system/source, modern or compatibility presentation, changed semantics, acceptance scenario and status. Retain engine files and authored data wherever possible. Where a rule is deliberately changed for usability, document the gameplay effect. Preserve choices and consequences instead of only preserving familiar names. Test full victory/defeat routes and multi-month campaigns. All original commands must remain reachable; compatibility presentation is acceptable only when it is readable and fully usable.

### Persistence and robustness

New/load/continue work after a normal restart. Autosave/manual save success is truthful. Permission failures, truncated JSON, unknown schema, invalid IDs and future-version saves produce a readable error without destroying the existing campaign. Temporary and backup recovery are explicit. Save RNG and pending operation state; repeated loading cannot duplicate rewards or advance time. Test fresh installation and upgrades using isolated directories.

### Usability, accessibility and presentation

At 1280×720, 1600×900 and 1920×1080, important actions and information remain readable and reachable. Long names, large rosters, empty searches, disabled states, scrolling, tooltips and dialogs fit. Keyboard users can navigate, activate, go back and dismiss overlays without a mouse. Selection/focus does not depend solely on color. Body text, contrast, scaling and motion settings are reviewed against actual captures. New players can understand the first objective, expected cost/risk, result and next action without knowing original keyboard commands.

### Performance and package

Measure a baseline on the actual machine, including populated campaign screens, large rosters and demanding tactical views. Record warm frame-time and memory samples rather than treating a fixed-FPS movie as a performance benchmark. Build with the pinned Flutter SDK and the target platform's supported toolchain. Exclude development helpers, tests, reports and unused assets while retaining required data and credits. Run the package outside the development server where applicable with isolated player storage; complete the full smoke scenario and inspect logs. Record OS/browser, CPU/GPU, Flutter/Dart versions, renderer, resolution, artifact hash and known limitations. For web delivery, explicitly verify persistence across reload/restart and offline launch behavior; do not assume a hosted page is an offline package.

### Provenance and release evidence

Keep upstream license/attribution and any bundled font/audio/art licenses. Generated assets have a manifest with prompt, generation date, destination, intended use and import settings. The release report distinguishes implemented features, verified scenarios, skipped checks and remaining limitations. A playable alpha is valuable progress but must not be called a production-ready complete modernization.

## Current evidence and next integration decision

The RacingDynasty workflow and installed engine/template inventory above are verified. The integration lead reports the upstream Dart/Flutter code count and selects engine retention as the architecture. LCS implementation, asset creation and release validation are assigned to other owners and remain unverified by this planning document. Update milestone status only from their concrete artifacts and reproducible evidence.

Next: finish provisioning the local Flutter SDK, launch the original, implement/test the semantic command bridge, reconcile the source-system inventory with complete screen navigation, and integrate the modern title/HQ/art contracts without changing retained gameplay.
