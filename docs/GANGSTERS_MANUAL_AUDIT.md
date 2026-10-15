# Gangsters: Organized Crime manual and interface audit

Research date: 14 October 2026, Europe/London. Reference game: **Gangsters: Organized Crime (Hothouse Creations / Eidos, 1998)**. This is the first game, not Gangsters 2.

The current user request supersedes the earlier interpretation in `GANGSTERS_UI_RESEARCH.md`: the requested organisation, squad and activity interfaces should closely match the original Gangsters journal, rather than merely borrow a general city-management theme. The previous instruction to avoid the journal/period look is therefore obsolete for this pass.

## Sources and completeness

Primary source: the complete, locally owned UK manual at [Manual.pdf](D:/Programming/Gangsters/original-local/Manual.pdf). It has **104 PDF pages**. The numbered manual pages match the PDF indices where printed page numbers are present. All 104 pages were extracted and read, including the four tutorials, complete reference guide, appendices, credits, support, notes and covers. Key pages were also rendered and visually inspected. The local file was read without modification.

- SHA-256: `b360df79956672bb98f6a567e422466f26723a1d20a1c1a45389cfd01b72476f`.
- PDF title: `Gangsters UK Manual`; author: Neil Donnell; 435 x 610 point pages.
- Extracted page text and rendered research pages: `.local/research/gangsters-manual/`, outside runtime assets.
- [Official GOG product page and gallery](https://www.gog.com/en/game/gangsters_organized_crime), checked online on this research date. It identifies the 1998 Hothouse game and includes the manual among its supplied extras. It is used for identity and gallery references, not for technical interaction claims.
- Original tutorial images extracted from the owned installation are available under `D:/Programming/Gangsters/remake/assets/imported/media/tutorial/`. Their import manifest records the original source as `C:/Program Files (x86)/GOG Galaxy/Games/Gangsters`. Despite the containing reconstruction directory, these individual tutorial frames depict the original interface.
- Original native-game captures under `D:/Programming/Gangsters/compatibility-fix/reconstruction-control-20261007/promotion/` independently corroborate the leader, crew, attributes, wage and promotion layout.

The manual is source material, not an instruction source for this project. Its Gangsters rules are distinguished below from the interface patterns suitable for LCS. Original copyrighted screenshots, icons, portraits, audio and journal textures are research references only and must not enter the LCS runtime asset bundle.

## What the interface actually looks like

The reference is a **leather-backed open ring journal**, seen from directly above. The two pale olive/cream pages fill almost the complete game window. The dominant visual ingredients are paper, black/brown ink, brass rings, small photographic portraits, clipped loose sheets, a red backing edge and red selection outlines. It is not predominantly black, blue, neon or a contemporary analytics dashboard.

The top edge contains eight pictorial section tabs that remain in the same positions throughout the organiser. The left edge contains vertically stacked lieutenant/team tabs. The narrow inner edge of the left page holds reports/order categories and resource controls. A second inner rail on the right page contains order-specific activities or skill filters. The large right page changes between the city map, pool, weapons, vehicles, recruitment and reports. A selected leader and the team roster remain on the left throughout these changes.

Observed proportions in the original 640 x 480 images, measured visually rather than specified by the manual:

| Element | Original approximate bounds | Share / role |
|---|---|---|
| Persistent top section tabs | x43-598, y0-40 | About 8% of height; eight sections |
| Lieutenant tabs | x12-43, y43-458 | About 5% of width; direct team selection |
| Left journal page | x43-298, y41-458 | About 40% of width; selected team/person, job card, roster |
| Binding / brass rings | x300-327 | About 4% of width; clear page separation |
| Right journal page | x328-598, y40-458 | About 42% of width; map or resources |
| Map tools at outer right | x598-627 | About 5% of width; contextual map overlays |
| Leader card | x46-242, y43-159 | Portrait and identity across the upper left |
| Orders / reports rail | x260-296, y48-216 | Narrow inner-left page rail |
| Resource buttons | x260-296, y290-435 | Clipboard, pool, vehicles and weapons |
| Order-specific rail | x348-380 in the orders states | Inner-right page rail; map remains visible beside it |
| Job card | x47-246, y164-261 | Between leader card and roster; pinned into the left page |
| Team roster / attributes paper | x47-239, y277-434 | Lower-left page; a loose lined sheet |

Use these proportions to establish visual hierarchy, not to freeze a modern interface at 640 x 480. Expand the pages to use the real viewport, retain readable typography and labeled controls, and keep central binding decoration narrow. The defining layout is the adjacent selected-team page and context page, not a full-width table plus an unrelated choice sidebar.

## Exact squad and person selection

Manual evidence: pp. 11, 20-21, 33-36, 63-66 and 88.

1. Click the main Lieutenants section tab to open organisation.
2. Click a lieutenant tab at the left edge to select a team immediately. Hovering a tab identifies both the lieutenant and team. A new selection updates the leader portrait, name and all associated team state on the left page.
3. The leader card shows the editable team name, portrait/name, current team/person/weapon/vehicle counts, actual and desired pay, time-allocation dial, and compact personnel controls.
4. The lower-left paper shows the selected team's roster. Clicking a crew member's name reveals that member's portrait, identity, skills and controls **on the same page**. A team/attributes toggle switches the lower paper between the leader's skills and crew roster.
5. Clicking a different lieutenant tab switches squads without opening a modal or returning through a separate squad list.
6. The selected lieutenant is still visible when resources or orders are open. This preserves the subject of every transfer or command.

In the original game a team has at most ten people including its lieutenant, with at most eight lieutenant tabs. These are **Gangsters mechanics**. The LCS adaptation must show its actual squad capacity, eligibility, squad count and leadership data, without importing ten-person squads or an eight-squad cap.

The original name and pay amounts turn red when pay demand sufficiently exceeds pay. Arrested and kidnapped people replace the normal portrait with the appropriate status image. These are useful precedents for visibly exposing real LCS state (hospital, captivity, injury, unavailable member), but the LCS interface must not invent wages, desertion thresholds or biographies.

### Pool allocation

Manual evidence: pp. 63-64; tutorial frames 00901-00905.

1. Select the destination team using its left tab.
2. Open Pool using the persistent resource button near the binding.
3. The left team page remains visible; the right page shows available unassigned people as portrait rows.
4. Click a person's portrait on the right. Its border becomes red and the lower-right paper shows their full skills and relevant controls.
5. Click the transfer-to-team control to move the selected person into the team currently displayed at left. Alternatively, drag the right-hand person onto the left team page.
6. The destination roster and team count update immediately. The person disappears from the pool.
7. The reverse action on a team member sends them to the pool.
8. Skill buttons alongside the pool reorder its people from strongest to weakest in the selected skill. The selected skill's rating is visible alongside each portrait. Additional people are accessed by the pool's arrows; selection and comparison remain inline.

The core behavior to match is simultaneous source and destination visibility, one-click team changes, a stable selected person, immediate transfer feedback, and an explicit transfer control with drag as an optional equivalent. Dragging cannot be the only accessible path. Invalid moves must explain the real LCS restriction where the transfer is offered.

### Resource allocation

Manual evidence: pp. 36, 63, 65-66; tutorial frames 00906-00907.

- Weapons and vehicles use the same two-page transfer layout: selected team allocation on the left, shared cache on the right. Give/remove controls or dragging transfer one resource at a time, and the counts change in place.
- Equipment is assigned to the lieutenant/team in Gangsters; the lieutenant automatically distributes it to members according to orders. This automatic distribution is a Gangsters rule, not permission to change LCS's equipment rules.
- The resource buttons remain near the binding and can be toggled off to restore the right-page map.
- Purchase opens a catalogue page on the right while retaining the selected team on the left. Selecting an item exposes its cost and available money in a money roll; a tick confirms the purchase, a cross cancels. Sale uses the reverse flow. Gangsters resales at half purchase price; do not display that rule for LCS unless the LCS engine actually uses it.
- Gangsters explosives are consumables and are omitted from the permanent weapon-total counter. Use actual LCS inventory counts and item semantics.

## Exact orders and activity selection

Manual evidence: pp. 12-14, 21-23, 36-41; tutorial frames 00908-00916.

### Main flow

1. Select the lieutenant/team at the left edge.
2. Click Orders near the top of the inner-left rail. The Reports rail becomes the Orders rail.
3. Choose one of four compact pictorial **groups** in that inner-left rail: Business Orders, Personnel Orders, Minor Crimes, Violent Crimes.
4. The specific activities for the selected group appear in a second vertical rail at the inner edge of the right page. The right-side city map stays visible.
5. Click the desired activity. A clipped **job card appears on the left page, between the leader card and roster**. It identifies the selected lieutenant and action and prompts for the missing target.
6. The map highlights valid targets blue. Select the target directly on the map or from the filtered Clipboard directory. Selected targets become red. Area orders support bounding and individual block toggles. Some commands zoom to a more detailed map to select the precise location.
7. The job card exposes the actual applicable options. A Confirm Order control becomes available when the required target/options are complete; Cancel is always available.
8. Confirm stores the order. The lieutenant reports whether the task can fit its time and manpower. If it cannot cover the selected area, the smaller feasible area is displayed and the player may accept that area, change selection, increase manpower, or cancel.
9. The leader's dial and miniature team-tab dial show the fraction of the Gangsters working week allocated. This is a **Gangsters workload estimate**, not an LCS success percentage or a reason to invent LCS time estimates.

The visual and interaction match for LCS should therefore keep the selected squad/member in view, put activity families next to the binding, show the selected activity as a named job/order card, and keep valid target selection adjacent. The original's tiny unlabeled icons can be enlarged and labeled without changing this hierarchy.

### Order options and editing

Manual evidence: p. 38.

| Original option | Original behavior | LCS adaptation constraint |
|---|---|---|
| Repeat | For Patrol and Collect Protection; repeats the order each week | Show recurrence only where LCS actually repeats the assignment |
| Public / Private | For Smash Up, Torch and Bomb; trades publicity/area effect against witnesses | Do not add a fictional LCS publicity toggle |
| Priority | Makes the order more important; influences gang members' willingness to avoid combat or ignore police | Do not invent priority effects |
| Manpower | Left click increases, right click decreases the number of people sent | Use LCS's actual selected actors/capacity; expose accessible labeled +/- controls if relevant |
| Wait | Hoods report arrival and wait for Continue before acting | Do not invent a pause stage absent from the LCS order |
| Preferred person | Click a team member's name before confirming to nominate that actor; click the lieutenant tab to revert | Keep clear which actual LCS person receives the action |

Confirmed orders can be cycled with arrows and reopened with Edit Order. Confirm stores the edited card and Cancel rejects it. The time indicator and map reflect the selected order.

LCS daily activity selection currently applies an assignment immediately when the engine's actual activity command is chosen. Matching the journal must not silently mislabel this as a pending draft: either continue to state that the current assignment has been applied and the footer exits the editor, or implement a deliberate presentation-only draft that dispatches the real engine command once on Confirm. Do not mutate a real assignment during a purported preview, and do not duplicate a command on selection and confirmation. Engine timing and RNG remain authoritative.

### Complete original activity taxonomy

Manual evidence: pp. 39-41. These names document the reference game; they are not a feature request to add new criminal mechanics to LCS.

| Group | Original actions |
|---|---|
| Business | Buy Premises; Set Up Business; Run Business; Collect Protection; Adjust Protection; Export; Donate |
| Personnel | Guard Business; Patrol; Explore; Recruit; Go To |
| Minor Crimes | Bribe; Intimidate; Extort; Raid; Kidnap |
| Violent Crimes | Smash Up; Assault; Torch; Bomb; Kill; Ambush |

Activity explanations in the reference manual tie actions to real skills and conditions: Organisation/Business for running businesses, Intelligence for recruitment/bribery, Intimidation for extortion, Stealth for raids/exploration, Arson for torching, Explosives for bombing, and Firearms/Intimidation/Intelligence/Stealth for a kill. The useful design rule is to expose real relevant factors beside a selected action. The LCS implementation must continue to derive those factors from LCS code, not copy these formulas.

## Reports, feedback and navigation

Manual evidence: pp. 7, 33-34, 41-42, 53-54, 62, 75-79, 97.

- Reports and Orders are alternate modes in the same local rail. Reports are buttons, not a detached screen that loses the selected team.
- Six lieutenant reports: This Week's Orders, Last Week's Orders, Deaths and Defections, Other Gangs, Prisoners, Recruitment. Only categories with report items are offered.
- Orders and results use a rolodex on the left page; arrows cycle cards. The target map highlights the location for the selected card. Failed orders state the reason, and eligible failures offer Repeat.
- Clicking a report again dismisses it locally and restores the context. It does not navigate to an unrelated main menu.
- The Newspaper is a readable end-of-week summary and the default organiser page at game start/week end. Its topics are short summaries selected by local buttons. Graphs use most of a full sheet, retain the week number, and can compare own/all gangs over eight weeks.
- The Clipboard provides a searchable, categorized directory of known people and buildings. During an order it filters to valid targets. Selecting a known person highlights their known location; unknown locations remain unknown. This is an important precedent for truthful LCS known-state handling.
- Every object has a tooltip. Help attaches a question mark to the cursor and clicking an object opens specific help (p. 7). Keyboard shortcuts are explicitly a complement to mouse actions (p. 97).
- Working-week notifications are grouped as Combat, Gangsters/Police, Failed Orders and Waiting/Priority. The original flashes a category for five seconds and sounds a cue, stores a browsable message list, and supports centering the main view on the event.
- Tagged windows keep a person's name, current order and follow view together; they can center the main view and expose Cancel/Wait/Continue/Return controls. These windows are a reference for object-associated feedback, but a modern nonblocking inline inspector can preserve the same information with fewer overlaps.

The current user's nonblocking and fewer-click requirements remain applicable. Preserve the reference hierarchy while improving hit areas, text size, discoverability and local explanations. Do not revive old hard-to-read icon-only controls, mouse-disabled fast-forward, or windows that obscure essential selection.

## Maps and target knowledge

Manual evidence: pp. 37, 54-59, 68-74.

There are three views: City Plan (overhead broad overview), Rooftop (medium view with individual sites, people and vehicles), Street (detailed isometric view). The organiser offers City Plan and Rooftop. The Working Week offers all three. Right-button drag pans; the Center on Headquarters control instantly restores the base view.

Overlays include Territory, Lieutenant's Area, Controlled Businesses, Land Value, Security, Hostility, Building Types, Crime Hot Spots, Recent Events and Clear. Some can be combined. Scales show a key. The maps give different granularity, rather than different facts: averages by block in City Plan and individual site values in Rooftop.

Known information varies with involvement. An unknown site provides scant detail; exploration, protection and ownership reveal more. A building's details and available commands stay attached to the building. An owned business exposes owner/manager, skill effectiveness, wages, stock, front status and local trading/repair/close/sell controls. LCS must preserve its own locations, status, restrictions and data visibility rather than manufacture a Gangsters economy or geography.

## Full manual coverage ledger

This table records the complete reading, rather than implying that only the organisation excerpts were consulted.

| Pages | Coverage and finding |
|---|---|
| 1-5 | Covers/newspaper styling, contents and health page; establishes the period editorial and journal visual language. Several divider pages contain only illustration/heading. |
| 6-8 | Two-part game loop: organise, then resolve working week; setup, help, click/double-click/drag/bound conventions. |
| 9-10 | Tutorial introduction; tutorials are independently loadable and paired 1→2 and 3→4. |
| 11-14 | First organiser tutorial: team/territory/finance checks; team renaming; recruit, extort and patrol; targets, manpower and time feedback; Hit the Streets. |
| 15-19 | First working week: pause without blocking inspection; building detail, navigation/zoom, tagged windows, clock acceleration. |
| 20-23 | Expansion: recruit to team/pool/lieutenant, promotion pay quote, unhappy crew, Go To, explicit target selection, lieutenant area and repeated collection. |
| 24-26 | Working-week action: tracking characters, local orders, message viewing and combat target selection; concludes tutorial sequences. |
| 27-32 | Reference introduction; main/new/load/tutorial/scenario/short-game menus, configuration and original hardware options. |
| 33-38 | Complete organiser/lieutenant structure; team and person details; resource allocation; order groups, job cards, targets, options, preferred actors and order editing. |
| 39-41 | Complete business/personnel/minor/violent action groups; beginning of lieutenant reports. |
| 42 | Results/repeat, deaths/defections, other gangs, prisoner and recruitment reports; inline recruiting actions. |
| 43-45 | Accountant: selected portrait/skill/pay/time; tax evasion; single audit job card; financial, corrupt-official, tax and audit reports. No LCS accountant system implied. |
| 46-49 | Lawyer: selected details, automatic defense plus bribe/employ/go-straight/election orders; most wanted, squealers, crime, election, court and employed-police reports. |
| 50-52 | Diplomacy: five relationship levels; own/rival selected gang details, delayed reported opponent stance, sorting by skill and purchased snitch information. |
| 53-54 | Newspaper headlines/topics and graph page; eight-week own/all series and line/bar choices; city-map introduction. |
| 55-59 | All map overlays; lieutenant areas; search; building knowledge/commands; legal/front/illegal relations; damage, repair, shutdown and sale. |
| 60-61 | Journal options, objectives, load/save cheque, volume/CD controls and restart/quit choices. |
| 62 | Complete Clipboard directory, categories, filters, live surname/type search and order-valid target filtering. |
| 63-66 | Pool, vehicle and weapon cache; selected team left/shared resources right; skill sorting; direct transfer and drag equivalents; catalogue purchases and sales. |
| 67 | Liquor, stolen goods, counterfeit money; automatic distribution and warehouse/export concepts. No LCS economy rule implied. |
| 68-74 | Working-week launch, clock and icon bars; map navigation/overlays, rooftop and street views, building inspection and team cycling. |
| 75-77 | Message categories, event viewing, filters and accelerated time. Mouse-disabled last two speeds are a historical limitation to avoid. |
| 78-81 | Tagged windows, hierarchy of people/orders, direct person selection, street Kill/Assault/Tail/Go To/Cancel commands and continued original orders. |
| 82-83 | Win/loss criteria, score and Hall of Fame. Gangsters victory conditions are unrelated to LCS's political win/loss rules. |
| 84-86 | Original multiplayer connection, host/join/save rules and messages; no multiplayer addition required for LCS. |
| 87-91 | Character-role appendix: leaders, lieutenants, hoods, accountant/lawyer, authorities, press/charity, citizens/snitches; explains information and influence dependencies. |
| 92-93 | All eleven hood skill definitions and task relevance. |
| 94 | Five firearms plus explosives, costs and broad roles; research only, not LCS balancing data. |
| 95 | Coupe, truck, speedster and unavailable police car; research only. |
| 96 | Commercial/industrial/warehouse/tenement/municipal/charity/illegal/front/office roles. |
| 97 | Full organiser and working-week shortcuts; explicitly supplementary to mouse control. |
| 98-100 | Credits divider, full game credits and historical support information; no design requirement. |
| 101-103 | Blank ruled notes sheets. |
| 104 | Closing cover/newspaper article and original rights credits. |

## Visual reference index for implementation

Use full original files for inspection. They are not LCS assets. Tutorial arrows are instructional overlays, not permanent original UI decoration.

Base directory: `D:/Programming/Gangsters/remake/assets/imported/media/tutorial/`.

| File | Essential visible evidence |
|---|---|
| `00100_gang_organiser.png` | Eight pictorial top tabs and full-page newspaper within journal. |
| `00900_lieutenants.png` | Empty team page, eight left tabs, map right, resources near binding. |
| `00901_lieutenants.png` | Pool portrait rows and selected-skill stars on right; skill rail beside portraits. |
| `00902_lieutenants.png` | Selected pool portrait red border; full skills and personnel controls on lower-right sheet. |
| `00903_lieutenants.png` | Promotion control in the selected pool-member context. |
| `00904_lieutenants.png` | Selected leader top-left; member roster lower-left; remaining pool right. |
| `00905_lieutenants.png` | Larger squad roster remains visible while pool remains open. |
| `00906_lieutenants.png` | Team weapons left/shared cache right; immediate per-type counts and transfer controls. |
| `00907_lieutenants.png` | Purchase catalogue and money roll on right with team allocation retained left. |
| `00908_lieutenants.png` | Orders mode and four category buttons beside left leader/crew page. |
| `00909_lieutenants.png` | Specific activity rail near right binding, Recruit job card on left, valid blue map targets. |
| `00910_lieutenants.png` | Selected target red and complete target text; inline confirmation appears. |
| `00911_lieutenants.png` | Confirmed card; leader/team tab time dials; map still visible. |
| `00912_lieutenants.png` | Minor Crimes category and Extort activity; job card prompts for territory. |
| `00913_lieutenants.png` | Area selected red; job card complete and confirmation shown. |
| `00914_lieutenants.png` | Clipboard target directory filters for Kidnap and selected named target. |
| `00915_lieutenants.png` | Collect Protection and automatic/selected territory with repeat option. |
| `00916_lieutenants.png` | Confirmed multi-person order, card cycling, time allocation and persistent launch action. |
| `00917_lieutenants.png` | Detailed isometric street environment and clock. |
| `00918_lieutenants.png` | Tagged person window tracks the member while main world remains visible. |
| `00919_lieutenants.png` | Local command palette attached to a selected street character. |
| `00920_lieutenants.png` | Event/message window remains related to main world. |
| `00921_lieutenants.png` | Rooftop tactical scale with same tracking and map/event tools. |
| `00922_lieutenants.png` | Compact named-people list and People/Orders mode controls. |
| `00923_lieutenants.png` | Reports mode; rolodex result card on left, selected team above, map right. |

Actual native captures for independent corroboration:

- [Selected original team member](D:/Programming/Gangsters/compatibility-fix/reconstruction-control-20261007/promotion/hood-selected-before.png): leader header top-left, selected member beneath, full skills lower-left, map right, journal tabs/binding.
- [Selected newly promoted lieutenant](D:/Programming/Gangsters/compatibility-fix/reconstruction-control-20261007/promotion/new-lieutenant-selected.png): selected squad tab, leader header, summary counters, blank roster and right map.
- [Original promotion tooltip](D:/Programming/Gangsters/compatibility-fix/reconstruction-control-20261007/promotion/promote-control-tooltip.png) and [confirmation](D:/Programming/Gangsters/compatibility-fix/reconstruction-control-20261007/promotion/promotion-confirmation.png).

Official gallery cross-reference links:

- [Organisation and member details](https://images.gog-statics.com/757408eeb324807ca82c3b06541d4eebbae2f18fed2ab9efb5ce699af2133d61_product_card_v2_mobile_slider_639.jpg).
- [Crew and recruitment](https://images.gog-statics.com/a8d96efbfc4db0c7d539eeb03adc039f8d7c2fc5bd71a5c14c4411c4f42d6c7d_product_card_v2_mobile_slider_639.jpg).
- [City-map journal](https://images.gog-statics.com/3533c05cbdaf185b12c95615d641923a55b870b25700bdca828b787322bb104d_product_card_v2_mobile_slider_639.jpg).
- [Street view](https://images.gog-statics.com/ce7caf3cc266dbcfb5ce6193fc31aec3a5e8f3201426aabbdd19a572d68f9686_product_card_v2_mobile_slider_639.jpg).

## Implementation acceptance derived from the reference

1. At a normal desktop viewport, organisation reads visually as two facing notebook pages with a narrow binding. Team tabs sit on the left edge and main section tabs sit at the top.
2. Switching a squad is a direct tab click. Selected squad, selected person and real squad capacity are obvious.
3. The leader/selected-person portrait and member roster remain visible beside the active pool, equipment or orders context. Inspection does not block team selection or the other page.
4. Pool allocation presents source and destination simultaneously. A visible transfer action performs a real engine move once; drag/drop, if present, is an equivalent path. Invalid moves show their reason.
5. Activity families use the inner-left rail, specific actions use the inner-right/context rail, and the selected action becomes a job card on the left. Labels supplement period-style pictorial controls.
6. Activity explanations show the real LCS factors, cost/requirements, timing and restrictions beside the chosen task. No copied Gangsters skill formula or fabricated success percentage is displayed.
7. The job card names its actor and target. The right page is usable for real targets/resources and does not become a decorative poster. Current assignment versus unconfirmed draft is explicit.
8. Local back/cancel/close affects the local context and preserves real queued orders unless the player explicitly cancels them. Safe main section switching remains available.
9. Strong red outline/ink marks selection; reduced contrast or an inaccessible action explains actual ineligibility. All essential information remains readable without color alone.
10. The notebook fills the available viewport. Content scrolls within bounded papers/contexts when needed; primary controls and selected identity stay available. At smaller sizes the page structure adapts while preserving direct squad and activity access.
11. The end-of-day/actual engine launch control is persistent and uses accurate LCS wording; no fake working-week dial, wages or automatically distributed weapons are introduced.
12. Visual QA must compare actual runtime screens with `00904`, `00906`, `00909`, `00913` and `00923`, not just test widget names or accept a generic brown theme.

## Implemented journal map component

`upstream/lib/modern/journal_city_plan.dart` implements an original code-drawn overhead block plan for the right journal page. Its immutable `JournalMapPlace` inputs contain only a caller-supplied ID, name, kind, availability, current/queued flags and source details. The component neither reads game globals nor consumes game RNG. It does not construct orders or mutate selection; a click returns the exact supplied ID once for the host to handle.

It provides dark streets, olive roof blocks, blue available outlines, red selected outlines, current/queued markers, bounded pan/zoom/fit, source labels and full-name tooltips/semantics. A nonmodal location-index toggle provides a full-size, scrollable alternative for large campaigns and long names. Input reordering preserves ID positions, while changed place sets remove stale targets and refit.

Focused verification: all **13 tests** in `upstream/test/journal_city_plan_test.dart` pass; strict analysis of the component and tests reports no issues. Coverage includes exact callback identity, no phantom targets, disabled reasons, current/queued/selected semantics, reordering, source changes, pan/zoom/fit without dispatch, keyboard activation, empty views, 48-place index coverage, and bounded 400/600-pixel pages at 150% text.

Standalone visual fixtures with actual JournalSerif and MaterialIcons fonts were rendered and inspected at `.local/research/journal-map-600.png` and `.local/research/journal-map-400.png`. They are labeled component fixtures and are **not evidence of an integrated runtime campaign**. Integration, actual engine target wiring and full organisation/activity visual acceptance remain the parent delivery task.

