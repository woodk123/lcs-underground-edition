import 'package:flutter/services.dart';
import 'package:lcs_new_age/modern/journal_sections.dart';

/// Optional presentation routes; the original LCS routes lead visible labels.
final journalSectionShortcuts = Map<int, String>.unmodifiable({
  for (final section in JournalSection.values) section.id: section.shortcut,
});

/// Exact routes through the original headquarters and asset-review readers.
/// Views with no matching original route deliberately have no entry.
final journalOriginalSectionRoutes = Map<int, String>.unmodifiable({
  for (final section in JournalSection.values)
    section.id: ?section.originalRoute,
});

int? journalSectionForKey(LogicalKeyboardKey key) =>
    JournalSection.forShortcut(key)?.id;

enum JournalGlobalCommand { saveAndExit, advanceDay }

const journalSaveShortcut = 'Alt+X';
const journalAdvanceShortcut = 'Alt+W';

final journalNavigationHelp =
    'Original LCS keys remain the main controls. At headquarters: '
    'L opens the Liberal Agenda, M opens Media, R reviews assets and squads, '
    'A assigns tasks, B opens sleeper assignments, E equips the squad, '
    'V opens vehicles, F opens operations, W carries out plans or waits, '
    'and X saves and exits. From R, V opens finances, 4 opens Justice '
    '(when available), and 0 opens the personnel directory. '
    'Keys keep the meaning of the current menu. A badge marked HQ shows '
    'a route to use after returning to headquarters.\n\n'
    'Optional global journal navigation: '
    '${JournalSection.values.take(JournalSection.values.length - 1).map((section) => '${section.shortcut} ${section.label}').join(', ')} and ${JournalSection.values.last.shortcut} ${JournalSection.values.last.label}. '
    'Alt+X uses Save & exit; Alt+W uses the available day/plans control. '
    'These commands follow the visible controls: required choices, dialogs '
    'and text fields keep their own input, and pending drafts block day advance.';
