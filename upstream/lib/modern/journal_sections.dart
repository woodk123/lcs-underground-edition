import 'package:flutter/services.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

// Retain the public IDs used by journal routes and existing callers.
const organisationJournalSection = 0;
const networkJournalSection = 8;
const peopleJournalSection = 9;
const basesJournalSection = 10;

enum JournalSectionDestination {
  headquarters,
  sourceReader,
  personnelDirectory,
}

/// Display order is independent of the stable IDs. Source keys describe the
/// original route; the shell must still resolve each live action and revision.
enum JournalSection {
  organisation(
    organisationJournalSection,
    'Organisation',
    JournalIcon.crew,
    LogicalKeyboardKey.digit1,
  ),
  people(
    peopleJournalSection,
    'People',
    JournalIcon.people,
    LogicalKeyboardKey.digit2,
    destination: JournalSectionDestination.personnelDirectory,
    sourceRoute: ['r', '0'],
  ),
  network(
    networkJournalSection,
    'Network',
    JournalIcon.network,
    LogicalKeyboardKey.digit3,
  ),
  bases(
    basesJournalSection,
    'Bases',
    JournalIcon.bases,
    LogicalKeyboardKey.digit4,
  ),
  ledger(
    1,
    'Ledger',
    JournalIcon.accounts,
    LogicalKeyboardKey.digit5,
    destination: JournalSectionDestination.sourceReader,
    sourceRoute: ['r', 'v'],
  ),
  justice(
    2,
    'Justice',
    JournalIcon.law,
    LogicalKeyboardKey.digit6,
    destination: JournalSectionDestination.sourceReader,
    sourceRoute: ['r', '4'],
  ),
  agenda(
    3,
    'Agenda',
    JournalIcon.diplomacy,
    LogicalKeyboardKey.digit7,
    destination: JournalSectionDestination.sourceReader,
    sourceRoute: ['l'],
  ),
  newspaper(
    4,
    'Newspaper',
    JournalIcon.newspaper,
    LogicalKeyboardKey.digit8,
    destination: JournalSectionDestination.sourceReader,
    sourceRoute: ['m'],
  ),
  reports(5, 'Reports', JournalIcon.reports, LogicalKeyboardKey.digit9),
  cityMaps(6, 'City maps', JournalIcon.city, LogicalKeyboardKey.digit0),
  options(7, 'Options', JournalIcon.options, LogicalKeyboardKey.keyO);

  const JournalSection(
    this.id,
    this.label,
    this.icon,
    this.shortcutKey, {
    this.destination = JournalSectionDestination.headquarters,
    this.sourceRoute = const [],
  });

  final int id;
  final String label;
  final JournalIcon icon;
  final LogicalKeyboardKey shortcutKey;
  final JournalSectionDestination destination;
  final List<String> sourceRoute;

  String get shortcut => 'Alt+${shortcutKey.keyLabel}';
  String? get originalRoute =>
      sourceRoute.isEmpty ? null : sourceRoute.join(' → ');
  String? get overviewKey => sourceRoute.length > 1 && sourceRoute.first == 'r'
      ? sourceRoute[1]
      : null;
  bool get returnsToOrganisation =>
      destination == JournalSectionDestination.sourceReader;

  static JournalSection? fromId(int id) {
    for (final section in values) {
      if (section.id == id) return section;
    }
    return null;
  }

  static JournalSection? forShortcut(LogicalKeyboardKey key) {
    for (final section in values) {
      if (section.shortcutKey == key) return section;
    }
    return null;
  }
}
