# Classic keyboard compatibility

The graphical presentation uses the original LCS readers for game keys and menu flow. The comparison baseline is the Classic `ConsoleWidget` feeding those readers, not a second implementation of the rules. Pointer previews and additional browsing views remain available without redefining source keys.

## Input contract

- Forward original game keys and repeat events without replacing a category default, task, purchase or destination choice with a preview.
- Keep the next awaited menu and original caller after Back. Enter, Escape, Space and X are interpreted by that reader, including readers where a key has another action or any key continues.
- Preserve case where the source distinguishes it, such as passenger and driver vehicle selection.
- Preserve source action identity/revision checks for pointer callbacks. A stale pointer draft cannot answer the next source prompt.
- Keep deliberate Tab traversal and focused control activation. Returning from a pointer-opened source menu restores game or text-entry focus, so incidental pointer focus cannot steal Enter/Space.
- Keep search fields and modal/help/inspection input isolated. Keys with no source interpretation do not clear drafts or switch chapters.
- Start prefilled text at the end. Enter and Escape finish `mvgetstr` with the visible edits; explicit GUI Cancel edits restores the starting value and has no Escape badge. Native editor/platform selection tools remain available.

## Reviewed reader families

| Family | Original flow and key behaviour | Verification |
|---|---|---|
| Title, save management and options | Source-authored choices and case; current reader owns Back | Title/creation labels; existing title, save and options regressions; creation/week browser journeys |
| Creation | Setup/identity letters, question choices and original acknowledgements | Existing creation flow/bonus tests and browser creation; exact current-action badges |
| Headquarters and asset review | R opens review; V closes back to R; roster and profile return one original level | Differential source-frame/campaign/RNG replay |
| Ordinary orders | A → actor; category defaults and numeric task keys apply immediately; X lays low; original Back returns to actor list | Differential desktop and enlarged replay; same four-key browser assignment in both views |
| Sleeper orders | Category defaults, role choices and recall retain source timing and one-level Back | Differential replay and pointer-entry Network journeys |
| Visits | F, district and site letters; site key queues immediately; Back moves one level and cancels at city root | Differential travel and source-alias tests; existing pointer destination and week journeys |
| Bases and investment | Source I/purchase keys spend/apply immediately; no added Enter; Back retains caller | Classic/graphical/pointer-started differential investment journey; pointer stale/version guards |
| People and profiles | Original person letters, roster paging, sort/reorder and source profile arrows | Differential roster/profile, repeat and rename; existing personnel and sorting journeys |
| Equipment, shops, recipients and vehicles | Exact live action and case-sensitive keys; original nested selection/Back | Existing actual-reader equipment, buyer, vehicle and shop regressions; raw dispatch audit |
| Ledger, Media, Agenda and legislation | Original page aliases, story letters, acknowledgements and parent return | Differential reporting, ledger aliases/history and existing required-report/legislation tests |
| Field operations, pursuits, treatment and recovery | Source movement/decisions, held keys and source Back; inspection cannot issue an order | Shared raw dispatch audit; existing tactical shell/action, pursuit, arrest and recovery journeys |
| Names and other text | End caret, Backspace and terminal-key result; guarded replay | Physical-key differential text plus explicit cancel and overlapping-submit regression |

The source audit checked every modern per-view keyboard handler. The only remaining local game-key readers are opt-in historical accounts and presentation dialogs. Live ordinary/sleeper/bases previews do not intercept source keys. Live reports and other menus delegate to the original await. The generic graphical source menu exposes the asset-review menu rather than silently replacing it with headquarters.

## Evidence and limits

Run the files listed under [Classic keyboard parity](TESTING.md#classic-keyboard-parity), the full suite, and `python scripts/shared_acceptance.py` with the pinned SDK. The shared runner builds one immutable artifact and records source identity and the browser-loaded JavaScript hash. Keep per-run logs, screenshots and counts under ignored `.local/` or `reports/`; they are evidence for that build.

The audit combines static dispatch review with declared reader journeys and existing gameplay regressions. It does not claim a manually played native campaign through every rare event or ending. No source gameplay rules, save fields or save compatibility identifiers are changed for keyboard presentation.
