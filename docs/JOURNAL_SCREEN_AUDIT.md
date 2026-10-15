# Journal screen audit — 15 October 2026

The hospital screenshot exposed a general presentation problem: many authored
events paint a new sentence onto a retained terminal screen and then wait for a
key. Rendering that entire buffer also displayed old headquarters commands,
status tables, and border characters. Other menus reused the seven-row character
sheet in panes too narrow for its original columns.

## Changes

428 existing any-key pauses across 41 source files now call `acknowledge` with
an appropriate report title. The helper collects text written since the previous
reader, omits unchanged background content and still-printed choices, and exposes
it to the existing journal notice view. There is still exactly one original
key reader. It does not clear the classic buffer, roll dice, alter simulation
state, or execute choices. Full-floor maps, articles, and the title screen keep
their dedicated renderers.

| Source family | Acknowledgements updated |
| --- | ---: |
| Daily activities, hospital/shopping, relationships, hostage events and sieges | 129 |
| Trials and prison | 38 |
| Congress, elections, constitution and Supreme Court | 26 |
| Conversations in and out of combat | 65 |
| Field actions, combat, encounters, pursuits and shops | 140 |
| Monthly and sleeper updates | 11 |
| Crew management and field guide | 7 |
| Television and media | 5 |
| Save import and errors | 2 |
| Siege location notices | 1 |
| Campaign outcomes | 4 |

Inline field acknowledgements use the map's existing report pane. Lower narrative
rows remain available; the ASCII map region is excluded. Movement stays disabled
for the awaited decision. The standalone report view has a readable text measure
and an always-visible Continue control.

The common character/squad printers now record snapshots of the information they
actually displayed. Menus can present compact portrait cards with equipment and
expandable attributes, skills and condition. Unknown values remain unknown;
restricted character information does not unlock a full dossier. Numbered rows
that explicitly mean unequip/remove, or belong to a nested recipient prompt,
retain their existing action-aware controls.

The original three-page personnel reader now uses the existing native dossier
for overview, skills and campaign/legal history. Its page navigation, rename,
gender, previous/next person and exit controls still dispatch the original keys.
Renaming uses the existing text reader.

The shared paged-list helper now exposes a choice when an old line builder only
painted a letter and label. It uses the helper's own letter-to-index mapping;
existing explicit actions take precedence. This fixes lists such as vehicle
types without inventing choices. Residual box-drawing furniture is suppressed in
the journal's generic report renderer while the classic console remains intact.

## Verification

- Full Flutter suite: **562 passing tests** after the shared changes.
- Final affected profile/report/field/keyboard group: **28 passing tests** after
  the final personnel control-label adjustment.
- Analysis of the affected engine, modern UI, display, daily, justice, politics,
  conversation, field, monthly, save and base modules plus the audit tests: clean.
- Release web compilation and offline-manifest injection completed.
- New tests cover current-only narrative, stale-choice overlap, one reader and
  one flush, Enter/Space/Escape acknowledgements, unchanged classic buffer and
  simulation/RNG state, restricted information, native profile pages, real
  car-theft transitions, and lower field narrative rows without the ASCII map.
- Widget layouts checked at 1280×720 and 800×600 with 150% reading size.
- Isolated Edge acceptance imports portable test fixtures and uses ordinary
  controls to open the original personnel reader, view skills, advance into
  car theft, select a car type, acknowledge two reports, reach the next choice,
  and receive an actual hospital admission. Large and small browser captures
  were inspected. It does not use a human browser profile or campaign storage.

Reproduce the focused tests from `upstream/`:

```powershell
..\.tools\flutter\bin\flutter.bat test --no-pub test/journal_screen_audit_test.dart test/field_prompt_test.dart test/journal_event_feedback_test.dart test/keyboard_navigation_test.dart
```

Reproduce browser acceptance from the checkout root against a built server:

```powershell
node scripts/journal_screen_audit.mjs http://127.0.0.1:8766/
```

Screenshots, semantic text, fixture copies, the served JavaScript SHA-256 and
browser results are written to `reports/journal-screen-audit/browser/`.

This is a source-wide audit of the shared presentation patterns, supported by
regression tests and representative real browser transitions. It does not claim
manual traversal of every random event branch. Existing dedicated journal title,
creation, recruitment, ledger, legislation, media, organisation, city and full-map
views remain responsible for their own content. Diagnostic exception screens and
the explicitly selected classic interface retain their diagnostic/terminal form.
