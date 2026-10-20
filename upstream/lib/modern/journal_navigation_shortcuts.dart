import 'package:flutter/services.dart';

/// Presentation routes use a modifier so original reader keys keep their meaning.
const journalSectionShortcuts = <int, String>{
  0: 'Alt+1',
  9: 'Alt+2',
  8: 'Alt+3',
  10: 'Alt+4',
  1: 'Alt+5',
  2: 'Alt+6',
  3: 'Alt+7',
  4: 'Alt+8',
  5: 'Alt+9',
  6: 'Alt+0',
  7: 'Alt+O',
};

int? journalSectionForKey(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.digit1 => 0,
  LogicalKeyboardKey.digit2 => 9,
  LogicalKeyboardKey.digit3 => 8,
  LogicalKeyboardKey.digit4 => 10,
  LogicalKeyboardKey.digit5 => 1,
  LogicalKeyboardKey.digit6 => 2,
  LogicalKeyboardKey.digit7 => 3,
  LogicalKeyboardKey.digit8 => 4,
  LogicalKeyboardKey.digit9 => 5,
  LogicalKeyboardKey.digit0 => 6,
  LogicalKeyboardKey.keyO => 7,
  _ => null,
};

enum JournalGlobalCommand { saveAndExit, advanceDay }

const journalSaveShortcut = 'Alt+X';
const journalAdvanceShortcut = 'Alt+W';

const journalNavigationHelp =
    'Journal tabs: Alt+1 Organisation, Alt+2 People, Alt+3 Network, '
    'Alt+4 Bases, Alt+5 Ledger, Alt+6 Justice, Alt+7 Agenda, '
    'Alt+8 Newspaper, Alt+9 Reports, Alt+0 City maps and Alt+O Options. '
    'Alt+X uses Save & exit; Alt+W uses the available day/plans control. '
    'These commands follow the visible controls: required choices, dialogs '
    'and text fields keep their own input, and pending drafts block day advance.';
