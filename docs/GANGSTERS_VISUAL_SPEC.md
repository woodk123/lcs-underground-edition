# Gangsters organiser visual specification

Research and original assets prepared 14 October 2026. This specification follows **Gangsters: Organized Crime (1998)**, specifically its Gang Organizer / Lieutenants section. It is not a general noir mood board.

## Evidence examined

- Local official manual: `D:\Programming\Gangsters\original-local\Manual.pdf`, 104 PDF pages. For this visual specification the tutorial on PDF pp. 11–14, organiser and orders on pp. 33–41, and resource allocation on pp. 63–66 were read in full; pages 33–41 were also rendered and inspected. The separate manual/mechanics investigation covers the complete manual.
- Native tutorial screens `D:\Programming\Gangsters\remake\assets\imported\media\tutorial\00902_lieutenants.png`, `00904_lieutenants.png`, `00906_lieutenants.png`, `00909_lieutenants.png`, and `00910_lieutenants.png`, inspected at their native 640 × 480 resolution. The last two are decisive for the subtype rail and job card placement during order selection.
- Actual selected-team capture `D:\Programming\Gangsters\compatibility-fix\reconstruction-control-20261007\promotion\new-lieutenant-selected.png`, inspected at native resolution.
- [Official GOG gallery](https://www.gog.com/en/game/gangsters_organized_crime), all twelve gallery images inspected. In particular images 3 and 4 show personnel allocation and image 11 shows the organiser with the city map. [Personnel allocation reference](https://images.gog-statics.com/757408eeb324807ca82c3b06541d4eebbae2f18fed2ab9efb5ce699af2133d61_product_card_v2_mobile_slider_639.jpg), [team skills reference](https://images.gog-statics.com/a8d96efbfc4db0c7d539eeb03adc039f8d7c2fc5bd71a5c14c4411c4f42d6c7d_product_card_v2_mobile_slider_639.jpg), [city reference](https://images.gog-statics.com/13913dd3ae1dc8ce65d549ab9c522cb45f4e4553812384f0a92323934b7507d8_product_card_v2_mobile_slider_639.jpg).

Original game screenshots and extracted manual images remain research references outside the production asset bundle. No original game bitmap, portrait, texture, or icon is used by the new UI.

## Composition to reproduce

The original organisation screen is one leather-bound, ring-bound **open journal**, not separate dashboard cards over a dark background.

At the original 640 × 480 resolution:

| Region | Native position / extent | Purpose |
| --- | --- | --- |
| Section tabs | Top, approximately y 0–40, eight illustrated tabs | Persistent section navigation |
| Team tabs | Far left, approximately x 12–43, y 40–457 | Portrait tabs select the current lieutenant/team; selected tab has a red edge |
| Left page | Approximately x 43–298, y 40–460 | Team name, leader portrait, summary, job card and crew/skills sheet |
| Binding | Approximately x 300–327, full page height | Red spine with three pairs of brass rings |
| Right page | Approximately x 328–598, y 40–460 | City map or resource list |
| Order subtype rail | Approximately x 348–380 during order selection | Concrete order icons, immediately right of the binding and left of the map |
| Utility rail | Approximately x 598–627 | Map filters and contextual utilities |
| Primary advance control | Bottom right | Hit the Streets starts the working week |

The left page occupies roughly 40% of total width and the right page roughly 42%. Team tabs and utility controls are narrow rails. These proportions, the physical book silhouette, and consistent locations are more important than reproducing 1998 text sizes.

Within the left page, the leader card sits at the top. Its portrait is about 60 × 80 native pixels, with ruled name fields to its right, summary icons below, and a circular time dial at the right edge. The middle space holds the **job card below the leader card** while an order is being prepared (manual p. 13). The lower paper sheet lists crew members, or switches to the selected character’s skills. Four round resource/navigation buttons sit near the inside page edge. The central orders/report strip is immediately beside the binding; it is not a separate wide right sidebar.

The right page defaults to the city map. Selecting Pool, Vehicles, or Weapons replaces that page with the relevant resource list while retaining the current team on the left. It must not open a blocking full-screen modal. The order subtype rail is contextual and sits at the **inside edge of the right page**, directly beside the binding; the map remains to its right. The manual's name "Right Panel" means a panel on the right journal page, not the outermost right rail. Native screenshots 00909 and 00910 establish this placement unambiguously.

## Original interactions that matter

| Original action | Observable result | Application to the LCS interface |
| --- | --- | --- |
| Click a left team portrait tab | Changes the displayed lieutenant and team immediately | Select the actual squad without a second confirmation or navigation detour |
| Hover a team tab | Shows lieutenant and team name | Provide a descriptive label/tooltip and keyboard focus label for each compact tab |
| Click a crew member’s name on the lower sheet | Shows that member’s portrait and facts | Inspect a real member in place; do not block the book or consume a simulation turn |
| Click the current lieutenant tab | Restores lieutenant details | Provide an obvious route back to the squad’s selected leader/member overview |
| Click Team / Attributes | Swaps crew list and skills sheet | Keep both views in the same physical page region |
| Click Orders | Changes the report strip into four order groups | Four compact illustrated groups, with a visible selected state |
| Click a group, then an order | Opens a job card below the leader, while the map highlights valid targets | Present the activity’s real description and mechanics in a job card, with deliberate apply/queue action where appropriate |
| Click a valid blue map target | Marks the selected target red | Differentiate inspectable, valid and selected objects with labels as well as colour |
| Confirm Order on the card | Stores the prepared order | Explain exactly when an assignment is applied, and separately when time advances |
| Click Pool / Vehicles / Weapons | Replaces the right page; click again closes it | Resources remain a page mode, preserving left-side squad context |
| Select a pool character | Red outline moves to their face and their details appear below | Clear single selection and explicit assignment action; drag-and-drop may be an alternative, never the only route |
| Click Hit the Streets | Executes the working week | Advance the actual LCS day/site departure using the existing engine command and truthful wording |

Original time allocation, ten-person teams, wages, lieutenant ranks, and the weekly schedule are **Gangsters mechanics**, not LCS mechanics. The visual system must not claim they exist in LCS. Preserve LCS’s actual squad capacity, assignments, requirements, health, equipment and daily timing. A paper card can explain those real rules without imitating unavailable systems.

## Materials and colour

The native screen is light olive ivory, subdued brass, red binding and dark ink. It is not a black-and-gold casino, neon noir, modern SaaS dashboard, or an all-brown distressed parchment map. Paper is lightly textured and clean. The small dark outer edge makes the open book legible; it should not consume usable page area.

Runtime palette is defined in `upstream/lib/modern/journal_theme.dart`:

| Token | Colour | Use |
| --- | --- | --- |
| page | `#E9E6CD` | Main olive ivory page |
| card | `#F4EFDB` | Job cards and readable fields |
| inset | `#E1DFC4` | Quiet recessed sections |
| ink | `#25291F` | Primary text |
| muted | `#585E47` | Secondary explanations |
| rule | `#A1A184` | Ledger ruling and dividers |
| brass | `#A29156` | Decorative hardware |
| brassLight | `#E1D5A7` | Ring highlights |
| brassDark | `#625431` | Hardware borders |
| binding | `#8C3829` | Red spine and selected tab outline |
| olive | `#455D35` | Primary action |
| selected | `#F2DFA2` | Selected tab/card fill |

All body ink on all four paper surfaces passes 7:1 contrast; secondary ink passes 4.5:1. State is always indicated by a label, outline or icon in addition to colour.

## Typography and readable density

Use the original journal’s serif character through **Libre Baskerville**, bundled locally as `JournalSerif` with regular and italic variable fonts. The official [Google Fonts source](https://github.com/google/fonts/tree/main/ofl/librebaskerville) and its SIL Open Font License are recorded in the asset manifest and the license is included in the offline asset bundle.

Use 14 px body text, 17 px section headings, and 23 px page headings as the starting scale. Allow the application reading-size control to enlarge these. Use tabular figures for health, money and current numeric facts. Avoid widely spaced uppercase headings and oversized marketing titles. Dense portrait tabs still need 42–44 px live hit targets. The original pictorial labels are supplemented by readable code-rendered names.

Generated paper is applied at 22% opacity over the flat page colour. Ruling is a code-drawn decorative layer at low opacity. Neither paper nor artwork should hide text. All names, values, costs, help, actions, state, and feedback remain selectable/live Flutter widgets; none are painted into a PNG.

## Original assets delivered

All five images were generated with the built-in ChatGPT image tool, copied byte-for-byte into both `assets/gangsters-journal/` and `upstream/assets/modern/`, with no pixel processing. The order atlas uses only the project's original generated navigation atlas as a style reference.

| Runtime asset | Size / format | Use |
| --- | --- | --- |
| journal_leather_v1.png | 1254 × 1254 RGB | Quiet oxblood leather swatch for outer edge |
| journal_paper_v1.png | 1254 × 1254 RGB | Very light ivory writing-paper microtexture |
| journal_portraits_v1.png | 1254 × 1254 RGB | Sixteen period-clothed adult portraits in exact 4 × 4 layout |
| journal_icons_v1.png | 1448 × 1086 RGBA | Twelve original pictorial icons with real transparency |
| journal_order_icons_v1.png | 1254 × 1254 RGBA | Sixteen original activity paintings with real transparency |

Portrait indices retain the established gender banks: female `[0,2,4,7,8,10,12,15]`, male `[1,3,5,6,9,11,13,14]`. They are illustrative likenesses, not new traits, and must never consume RNG or invent biography. The existing children/nonhuman fallback remains.

The icon atlas is logically 4 × 3, but use the inspected explicit crop rectangles in `journalIconSourceRects` / `assets/gangsters-journal/atlas_metadata.json`. Equal-cell cuts would clip a few paintings or include a neighbour’s edge. Icons 0–7 are crew, accounts, law, diplomacy, newspaper, reports, city and options. Icons 8–11 are business, personnel, activism and operations; their live labels and actual activities come from the LCS UI.

The order atlas is logically 4 × 4. Its symbols are donations, art, sewing, music, recruitment, study, teaching, medicine, graffiti, protest, newspaper, hacking, vehicle acquisition, prisoner tending, burial and laying low. Use the inspected `journalOrderIconSourceRects` from `journal_order_icon.dart`, not equal-quarter cuts. Mapping uses exact `ActivityType` enum values and changes no state. Unsupported activities keep a truthful conventional fallback; a wheelchair is not represented as a car, streaming is not represented as print journalism, and credit-card fraud is not silently recategorised as hacking. All labels and actual choices remain live controls from the original engine.

## Ready-to-use Flutter API

- `buildJournalTheme()` installs the font, readable colours, control styles and `JournalVisuals` art selection extension.
- `JournalPalette` contains colours, text styles and material asset paths.
- `JournalVisuals.portraitAsset` and `.iconAsset` let visual renderers choose journal art without changing campaign objects.
- `journalPaperDecoration(inset: true/false)` provides quiet paper decoration.
- `journalTabDecoration(selected: ..., enabled: ...)` provides an authentic tab edge and selected state.
- `JournalSurface(child: ..., padding: ..., inset: ..., lined: ...)` wraps live content in a paper surface.
- `JournalBinding(width: 26)` draws decorative red spine and three ring pairs, excluding semantics and input hit testing.
- `JournalIllustratedIcon(icon: JournalIcon.crew, size: 48)` draws the inspected original pictorial asset without adding a focus stop or input handler.
- `JournalOrderIcon(type: ActivityType.donations, size: 40)` draws the matching activity painting or a conventional unsupported-type fallback, without any input handler or game-state mutation.

## Layout and usability acceptance

The implementation should be checked in the actual running game at 1600 × 900, 1280 × 720, 1024 × 768 and 800 × 600, plus a narrow window and increased reading size. This art/theme delivery alone is not proof that the integrated layouts passed.

- The book uses the available viewport. The selected squad, its crew list, current assignment and four order groups are visible without scrolling the whole page.
- Squad tabs switch in one click. Crew selection stays in place. No modal is required just to inspect, select a group, choose an activity or see its mechanics.
- Order descriptions, costs, requirements, factors and timing are available in the job card before applying the real action. Unavailable orders explain why.
- The right page keeps map or resource context while the player works on a selected team. The active page mode and selected order are obvious.
- Section tabs remain visible; dangerous or incomplete engine decisions retain their original explicit completion flow.
- Long names and large rosters scroll inside their own paper sheet, while the leader card and primary action remain reachable.
- At narrow widths, preserve order and labels with a controlled page arrangement rather than shrinking text to native 1998 sizes or clipping controls.
- Decorative leather, rings, icons and portraits do not block pointer or keyboard interaction, change game state, spend resources or advance time.

Focused theme validation: `flutter test test/journal_theme_test.dart`; strict analysis: `flutter analyze --no-pub lib/modern/journal_theme.dart test/journal_theme_test.dart`. Integration and rendered-layout verification remain the root delivery responsibility.
