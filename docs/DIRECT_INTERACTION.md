# Direct interaction in the central workspace

The modern management view now makes the main content interactive. A person is a clickable roster row, an activity is a selectable card, and a destination carries its own action and conditions. The detached generic “Available choices” rail is removed by the shell integration. Keyboard shortcuts remain secondary hints.

This change responds to the rejected assignment-screen screenshot: putting an inert terminal report in a paper panel beside a second menu made the player translate names and keys instead of selecting their crew directly. The management principle is the same as the user's Gangsters reference: actions belong to named people and places. The game remains contemporary LCS, with its original simulation, satire and choices.

## Module and integration

`upstream/lib/modern/direct_content.dart` exports:

```dart
const DirectContent({
  super.key,
  required Console console,
  required ValueChanged<String> onAction,
  bool? textInput,
  Set<int> hiddenRows = const {},
  int maxColumn = CONSOLE_WIDTH,
});
```

The shell owns vertical scrolling and rebuilds on console revisions. `DirectContent` owns responsive tables, rows, menu cards, inline values and keyboard notes. `hiddenRows` and `maxColumn` allow the tactical shell to retain its graphical map without duplicating the old map cells in the report. The existing classic view remains the full-geometry fallback for specialist graphics.

Commands come exclusively from `ConsoleAction`, including exact key/case, enabled state and source identity. The renderer never invents a command from a visible letter. Source coordinates describe the relationship between a choice and its adjacent data; they are not invisible click overlays.

## Implemented behavior

- Engine-authored delimiter headers become actual proportional-font table columns. Names, skill, health, location and activity remain together. The complete row is a real button with hover, keyboard focus and a trailing affordance.
- The current activity and health fields have readable status treatment. The values and their engine colors are retained; the renderer does not reinterpret blood, armor, injury or skill numbers.
- Narrow layouts use labeled, clickable record cards with the same information and action identity.
- Task categories and their subactivities appear as real cards in their corresponding source columns. The engine's cyan selected state produces a checkmark and teal border. Confirm is prominent.
- A menu's current value, cost, restriction, adjacent description and following explanation remain attached to its card. Multiline origin answers retain their attribute effects.
- Destination names are directly selectable. “Need Car,” closed/siege/security state, heat/secrecy, current location and city descriptions remain attached to the corresponding destination.
- Equipment choices preserve their grid relationships and quantities. Footer paging, sorting and bulk controls appear as a compact central toolbar.
- Decorative terminal rules are omitted. Proportional report fragments preserve narrative and state data. Keyboard-only instruction prose is retained in an expandable “Keyboard & game notes” section.
- Synthetic nested engine choices are rendered separately when their coordinates do not describe the displayed text. They cannot overwrite unrelated report content.
- Disabled actions remain visible and inert. A callback from an old console revision is rejected. Case-sensitive driver/passenger commands retain their original raw key.

## Accessibility and test contract

Each action has one button semantic role and a stable name such as `A QA Founder`, `B Legal Fundraising`, `1 Solicit Donations`, or `Enter Confirm Selection`. Adjacent stats/descriptions are exposed as the semantic value. New controls use real `TextButton` widgets rather than gesture hitboxes over a console image.

Stable widget keys are `direct-action:<row>:<column>:<exact-key>`. A desktop roster table uses `direct-data-table`; the notes section uses `direct-keyboard-notes`. These are testing identifiers, not part of the game state.

The primary direct-interaction tests are owned by the programmer in `upstream/test/direct_content_test.dart` and `direct_flow_test.dart`. As of 13 October 2026, all nine new tests pass:

- Real engine assignment flow at 1280 × 800 and 800 × 600: click the person in the center, Legal Fundraising, change activity, choose Solicit Donations, confirm, and verify the engine assignment.
- Real destination flow at both sizes: click district and site in the center, verify an actual queued squad visit, and verify unavailable travel does nothing.
- Proportional roster columns and preserved adjacent values.
- Labeled compact records fitting a 560 px content width.
- Disabled controls remaining inert.
- Raw lowercase passenger versus uppercase driver action identity.

`dart analyze lib/modern/direct_content.dart` reports no issues. The new checks do not establish that every specialist engine screen has been manually reviewed; the shell's old expectation tests and graphical release captures are separate integration work.

## Visual acceptance

The final screenshot review should inspect the central roster, selected-person task categories, selected subactivity and confirmation, destination cards, and compact records. A player should be able to complete the task by clicking the thing they see, without matching a name to a letter elsewhere. No default management view should depend on monospace padding or ASCII rules for its visual hierarchy.
