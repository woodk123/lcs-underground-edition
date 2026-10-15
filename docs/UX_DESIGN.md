# Liberal Crime Squad — UX and visual design

## Product direction

Keep the upstream simulation and its decisions intact. Present the player as the organizer of a precarious political movement: plan a day, understand its consequences, adapt to the news, and keep people alive. The interface should make the existing depth discoverable rather than replace it with simplified mechanics.

Use a modern Flutter presentation around the preserved Dart game. The upstream README describes a console widget with no knowledge of game state; this is the source of the current navigation friction. Keeping the engine avoids rebuilding its interdependent politics, justice, combat, recruitment, injuries, economy, equipment, and save format. This is the strong reason to depart from the initial Godot preference. Adopt the useful Godot/RacingDynasty conventions—central theme, deterministic simulation, semantic actions, local assets, visual captures, pinned tooling—without forcing a runtime port.

The supplied reference image is a repository screenshot. Treat it as source identification, not as an intended game layout.

## Findings from the source

| Area | Existing behavior | Design implication |
| --- | --- | --- |
| Title | Continue with founder name; load/manage saves; new game; import; scores; changelog; gameplay options. | Put Continue first when a valid save exists. Keep save management and import visible. |
| Campaign setup | Three independent options: political climate, CCS rival strength, team-first or alternating initiative. | Preserve each option and its explanatory sentence. A simple difficulty label cannot express all three. |
| Founder setup | Generated given/family names, sex at birth, choose/random origin, starting city. Origin questions alter founder skills and attributes. Later, an editable public name is requested. | Keep the complete creation flow. Show progress and distinguish rerolling an identity field from typing a public name. |
| Starting state | One founder in an existing squad; funds start at $7 before origin effects. | Guidance should start with safe income, recruiting, and learning the city. Avoid pretending the player already commands a large organization. |
| Headquarters | Assign tasks, sleeper tasks, review people/form squads, equip, vehicles, plan visit, agenda, media, day advance. Selected squad or safehouse changes contextual controls. | Keep a stable HQ navigation shell and name the current selection. Context changes should not look like opening a new campaign. |
| Travel | City → district → site; selecting a site assigns a squad visit for the next day. Cars, funds, closed sites and sieges constrain travel. | Explicitly label the plan as queued. Show selected squad, destination and travel constraints before the day advances. |
| Daily tasks | Individual tasks have category submenus, prerequisites, skill dependencies and help. Bulk assignment and sorting already exist. Squad visits override individual activities. | Expose assignment state prominently. Preserve bulk actions; explain conflicts instead of silently replacing tasks. |
| Organization | Squads and people have location and activity; people also appear in active, hostages, hospital, justice, sleepers, dead and away lists. Equipment can be moved among sites. | The roster needs state filters. All these states must remain reachable even when empty. |
| Safehouses | Heat versus secrecy, food, fortifications, hacker den, video room, security and power upgrades matter. Sieges can prevent waiting. | Display danger as text plus a visual indicator. Crisis controls supersede ordinary planning controls. |
| Missions | Maps, movement, encounters, loot, equipment, talk, combat, flee/sneak, rescue/release and contextual use. Alarm and reinforcements escalate; known maps and infiltration matter. | Preserve the map and full available actions. Add readable encounter and alarm status, context help and an obvious escape path. |
| Political goal | Laws, public opinion, elected branches and courts progress independently. The campaign can end in liberal or conservative victory. | Keep the goal visible without collapsing issue-level depth into one score. |
| Media | Public liberal views and LCS approval are distinct. Articles have source alignment, date, unread state and issue-level impact. Violence increases heat and can alienate supporters. | After-action feedback should distinguish notoriety, approval, political effect and police attention. |

Primary source files: `upstream/lib/title_screen/title_screen.dart`, `new_game.dart`, `questions.dart`; `upstream/lib/basemode/base_mode.dart`, `plan_site_visit.dart`, `activate_regulars.dart`, `activate_sleepers.dart`, `review_mode.dart`, `media_overview.dart`, `liberal_agenda.dart`, `help_system.dart`; `upstream/lib/sitemode/sitemode.dart`; `upstream/lib/engine/engine.dart` and `console.dart`.

## Visual language

Use an editorial planning desk: ink, warm paper, precise rules, a restrained city illustration, and a confident serif masthead. Dense data should feel like an organized intelligence brief. Avoid fake scratched terminal effects, neon cyberpunk, glossy pill controls, decorative gauges, or protest imagery behind important text.

| Token | Value | Role |
| --- | --- | --- |
| Ink | `#182632` | Primary text, navigation, structural contrast |
| Deep ink | `#101C26` | Console canvas and title art overlay |
| Paper | `#F1EDE3` | Main page background |
| Card | `#FAF7F0` | Readable cards and dialogs |
| Rule | `#D4D0C5` | Dividers, neutral borders |
| Muted ink | `#647079` | Secondary text on light surfaces |
| Vermilion | `#A84335` | Primary commit action, danger accents |
| Teal | `#286A65` | Selected navigation, success and supportive trend |
| Ochre | `#9B712C` | Caution and queued status |
| Focus | `#2C6FA6` | Unambiguous keyboard focus ring |

Body type: bundled Source Sans 3 or an equivalent readable open-source sans. Headings: Source Serif 4. Console: a bundled monospace font; preserve full glyph coverage for maps, line drawing and symbols. RacingDynasty already bundles Source Sans 3 and Source Serif 4 under OFL, demonstrating a suitable local font workflow. Copy fonts only with their license and provenance.

Default body size 16 logical pixels, supporting copy 14, page title 30–36, masthead 40–54. Use semibold labels, sentence case, tabular numerals for money/dates/counts, and restrained tracking only for short section labels. Avoid continuous capitals in body copy. Body line height should be approximately 1.4. Operational labels should be clear; keep the original satire in descriptions and story text.

Use a central Flutter `ThemeData` and shared design tokens for spacing, colors, typography, cards, buttons, focus/hover states and tooltips. Keep one-off decoration separate from reusable controls. Primary buttons are filled vermilion; neutral buttons are warm paper with an ink border; selected navigation is teal with a textual label and visible edge marker. Disabled controls retain a readable label and explain why when the engine provides a reason.

## Artwork contract

Use ChatGPT image generation for a panoramic fictional American city and, if useful, a quiet safehouse planning-desk vignette. Style: painterly editorial illustration with ink silhouettes, warm paper, subdued teal, and sparse vermilion. Buildings and streets should read clearly at thumbnail scale. No real political logos, slogans, lettering, interface, baked-in buttons or labels.

The city can establish place on the title screen and the HQ banner. Crop intentionally, keeping the important skyline in the central safe area. Place real text on opaque or strongly shaded surfaces. Artwork is atmosphere; never use it as the only carrier of navigation or game state. Keep source images, prompt/provenance, optimized runtime versions and thumbnails organized. Ship locally and work offline.

## Information architecture

The application has a stable outer shell and an engine-owned inner screen. The outer shell offers orientation, game help, visual settings and save information. It may send game commands only when those commands are available in the current engine context.

At HQ, organize commands into five visible groups:

1. **Headquarters** — today's plan, active squad/safehouse, available actions, crisis notices.
2. **People & squads** — review/form squads; individual and sleeper assignments; equipment and vehicles.
3. **City** — plan visits and inspect destinations, with the queued squad visit visible.
4. **Politics** — agenda, public opinion and laws.
5. **News** — media overview, unread articles and impact.

Do not send a base-mode letter while inside a nested engine screen: the same letter can mean a different operation. Within detailed screens, use a breadcrumb and explicit Back action from the current engine options. Shell navigation that would leave the current engine flow must be disabled or resolved through an explicit engine-supported route. Avoid arbitrary sequences of injected Escape keys.

The recurring player loop is **Review → Assign → Plan → Execute day → Read outcome → Adapt**. The day-advance action remains in a stable position at HQ. It is the principal commit action, visually distinct from navigation. Use “Carry out plans” when visits are queued and “Advance one day” otherwise. Under attack, show the existing crisis route and explain that the attack must be resolved first.

## Title and onboarding

Create a bespoke title view with the game name, an editorial city illustration, a brief premise, and a compact action panel. Preserve version and credits. Continue shows founder/campaign identity when available. New Campaign is available without a save. Load/Manage, Import, Settings, Scores and Changelog remain accessible without hiding essential actions behind icon-only menus.

Offer a first-run guide that can be dismissed and reopened. Keep it to four actionable points:

1. Assign people a task. Legal fundraising can keep a new movement solvent.
2. Assemble and equip a squad before planning a site visit.
3. Plans happen when you advance the day. Inspect the destination and risks first.
4. Read the news. Public liberal views, squad approval, and police heat are different things.

Guidance explains existing mechanics and never changes difficulty, grants equipment, skips origin questions or creates alternate game state. Persist the dismissed state locally. Do not block experienced players with repeated tutorial modals.

For creation, use a heading such as “Found your movement” plus a short “Campaign settings / Founder / Origin / Begin” progress indicator driven by actual engine context. Retain origin story text and all options. For text-entry screens, provide a real labeled text field with caret, submit and cancel affordances only where supported; never treat a typing prompt as an “any key” advance screen.

## Headquarters composition

Desktop layout:

```text
Application shell
├─ Masthead: campaign name · date · funds · help · settings
├─ Row
│  ├─ Navigation rail: HQ / People / City / Politics / News
│  ├─ Flexible main column
│  │  ├─ City banner + selected squad / location identity
│  │  ├─ Today: assignments, squad plan, clear danger state
│  │  ├─ Roster / safehouse / detailed engine view
│  │  └─ Persistent explanatory status and latest feedback
│  └─ Context panel
│     ├─ Available actions as labeled buttons
│     ├─ Selected command help / prerequisites
│     └─ Advance day / execute plans
└─ Footer: keyboard hint · autosave status · engine version
```

Use the active squad and safehouse from the game state, not text parsing or a parallel model. Show squad name, member count, location and assignment. People rows should expose name, health, strongest relevant skill, location and current activity; detailed injuries and all attributes stay available by inspecting a person. If the initial delivery uses the preserved console for these detailed lists, ensure they remain readable and the real action controls surround them.

HQ summaries must refresh after every completed engine frame. Selection and command feedback must never lag behind the displayed roster. An empty organization view explains the next action and offers the existing form-squad route. A person under a squad visit is labeled as committed to that visit; do not imply an individual task will also execute.

## Semantic action panel

`addOptionText()` delegates to `addInlineOptionText()` and already carries key, label and enabled state. Capture those structured values when the engine renders, then publish a complete immutable frame when it flushes. Do not infer controls solely from OCR or colored pixels.

The UI contract should include a stable per-frame identity, readable label, exact dispatch key, enabled state, and source coordinates/order. Source order helps group categories and choices. Keep repeated keys if they belong to distinct visible rows; do not accidentally discard a valid action by globally deduplicating key characters. Preserve case-sensitive input where the game expects it, including vehicle driver selection. Page and arrow actions must dispatch their actual control keys rather than the first letter of their displayed name.

Strip console color markup from the label without losing the text. Separate the displayed shortcut from the action name. Keep original meaning; only use a friendlier label where the route is understood. “Any key,” Enter, Backspace, Escape, arrows and Space are distinct intents. Disabled actions must not dispatch. A pointer click should activate once, and an old button should be invalid as soon as a new frame replaces it.

Do not expose decorative color changes as controls. Avoid automatic activation on hover or focus. Do not invent action availability from assumptions about the selected game mode. A context help panel may contain explanatory copy, but only the engine decides what can be done.

The original console remains the complete detailed view for maps, encounters, narrative and screens not yet replaced. Preserve its 80 × 25 geometry and color distinctions. Include an obvious “Game view” label and a compact keyboard legend. Support keyboard and pointer input together. An enhanced shell is not permission to remove the complete view.

## Mission and outcome feedback

Show the current site and floor prominently. Keep movement/map controls accessible without opening a drawer on a normal desktop window. Group mission commands by purpose: Move, Interact, Squad, Exit/escape. Preserve every enabled existing command, including rescue/release and context-dependent Use.

An alarm is a named state: quiet, suspicious, alarmed, reinforcements incoming/responding. Match the engine's actual states; avoid invented countdown precision. Pair warning color with text and a clear icon. The map legend explains the player, exits, doors, loot, encounters and floor changes. Do not decorate away unknown areas or make the entire site appear discovered.

After a day or encounter, preserve the complete messages and make the important change easy to spot: money earned/spent, new recruits, injuries, arrests, heat changes, article impacts and assignment completion. Distinguish actual results from estimates. News impact should remain attributable to an article and issue; do not combine approval and general public opinion into a misleading single progress bar.

## Keyboard, touch and accessibility

All new buttons have semantic labels, visible keyboard focus, logical traversal and a minimum 44 logical-pixel touch target. Tab moves between UI controls; Enter/Space activates the focused control; Escape uses the current available back route. Focus returns to a sensible control after closing a help/settings dialog. Do not steal text-field input for game commands.

Show shortcut badges as a convenience. The pointer user should never need to memorize a letter. Keep direct engine keyboard input for experienced players. Where the original engine has unconventional movement (`W/A/D/X`), label it accurately; do not silently claim standard WASD controls.

Use labels in addition to red/green color, readable contrast on every surface, selectable text where practical, and text scale controls. Respect reduced-motion preferences. Motion should be limited to short state transitions and subtle focus/hover feedback; no flashing alerts. Keep story content and tone settings available from the original options flow.

Localization should use central semantic UI keys for new shell strings, with placeholders applied after translation. Preserve original game text until its full translation pipeline is addressed. Prepare layout for longer strings and RTL through the framework's inherited directionality; do not mirror fixed map coordinates. Plurals are needed for people, squad members, days, articles and money-related counts. Context is needed for “squad,” “site,” “activity,” “support,” “heat” and “secrecy.”

## Responsive behavior

Design at 1440 × 900 and verify 1280 × 720, 1024 × 768, 1920 × 1080 and 2560 × 1080. The main column expands; readable text does not stretch into an excessively long line. Cap article paragraphs to a comfortable reading width.

At wide widths, show navigation, main content and context actions together. Below approximately 1180 logical pixels, collapse the navigation to a labeled compact rail and move secondary context content below the main view. At narrow widths, use a top navigation menu and a persistent action opener; content and actions scroll vertically. The console keeps its geometry with deliberate fit/zoom controls and, when necessary, horizontal scrolling. Do not shrink 80 columns into illegible phone text or hide the only available escape control.

Support window resizing during play and text scale from 100% through 150%. Prefer constraints, flexible rows/columns and scrollable content to fixed coordinates. Decorative art can crop; game information and controls cannot. Test a phone viewport as an additional compatibility check, while the first production target remains desktop web/Windows unless a native mobile release is explicitly scoped.

## Godot contingency

If a later decision moves presentation to Godot, use a `Control` root with Full Rect anchors and an inherited `Theme`; menu scenes remain independent. The equivalent hierarchy is:

```text
Control (Full Rect, locale direction)
└─ MarginContainer
   └─ VBoxContainer
      ├─ PanelContainer > HBoxContainer (masthead/status)
      ├─ HBoxContainer (expand/fill)
      │  ├─ PanelContainer > VBoxContainer (navigation)
      │  ├─ ScrollContainer > VBoxContainer (main content)
      │  └─ PanelContainer > ScrollContainer > VBoxContainer (actions)
      └─ HBoxContainer (footer)
```

Use `canvas_items` stretch with `expand`, a 1440 × 900 reference canvas, container-driven layout, and a central `.tres` theme. Use actual buttons, labels, rich text and text fields, never a screenshot of the UI. Logic would bind emitted view models to Controls and invoke typed engine actions in both GDScript and C#; no such Godot logic is introduced by this design document because the chosen delivery preserves the Flutter runtime.

## Acceptance checks

Release-blocking checks:

- A new player can start a campaign, choose all three campaign settings, complete founder/origin creation and reach HQ using the pointer.
- A returning player can identify and continue a valid save; load/manage/import remain usable; saving and restoring retains engine state.
- From HQ, the player can inspect a person, assign a legal income task, advance one day and identify the result without memorizing a key.
- Form-squad, equip, vehicles, sleepers, politics, media and travel routes remain reachable whenever the original engine enables them.
- A planned visit is visibly queued; advancing the day performs it. An active attack clearly blocks ordinary waiting and exposes the crisis route.
- Every captured action dispatches the exact existing engine key once; disabled and stale actions dispatch nothing; controls update after nested-screen changes.
- Full detailed screens remain available, including mission maps, creation questions, text entry, shops, injuries, justice and news.
- Keyboard-only play works through creation, HQ, an assignment, mission movement and returning to HQ. Pointer controls do not swallow text entry or break focus.
- No overflow, clipped primary action, unreadable console or unreachable Back/escape at the target desktop sizes and 150% text scale.
- Graphical captures are inspected for title, HQ, founder creation, tasks, travel, politics, news and a mission. Record screenshots and any intentional limitations.
- Game and local artwork work offline; fonts and asset provenance are bundled; no API key or network service is required to play.

Polish checks:

- New shell colors pass a contrast check; warning/success state remains clear without color.
- The first-run guide is useful, dismissible, persisted and reopenable.
- Portrait artwork has no baked-in text; paragraphs have comfortable line lengths; status cards use the same vocabulary as the underlying screen.
- Loading, saving, invalid input and failure feedback are visible and actionable.
- New UI strings are centralized; long-label and RTL layout previews do not break navigation.

## Practical delivery order

1. Preserve and test the upstream engine and saves; publish structured frame/actions safely.
2. Build the theme, title view, responsive shell and context action controls.
3. Build HQ from real game state, including clear selection, queued tasks and day execution.
4. Add the first-run guide, contextual help, keyboard focus and readable detailed view.
5. Integrate generated artwork and bundled fonts, then capture and inspect the complete first-session loop.
6. Verify complex routes and save round trips; document remaining UI limitations honestly before calling a release production ready.

Do not use a polished title screen as a substitute for exercising the full game. Production readiness is established by complete interaction, state preservation, appropriate testing and visual QA.
