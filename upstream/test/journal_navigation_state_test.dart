import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_navigation_state.dart';
import 'package:lcs_new_age/modern/journal_sections.dart';

void main() {
  test('display order keeps historical IDs and original keyboard routes', () {
    expect(JournalSection.values.map((section) => section.id), [
      0,
      9,
      8,
      10,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(journalOriginalSectionRoutes, {
      9: 'r → 0',
      1: 'r → v',
      2: 'r → 4',
      3: 'l',
      4: 'm',
    });
    expect(journalSectionForKey(LogicalKeyboardKey.digit2), 9);
    expect(journalSectionForKey(LogicalKeyboardKey.digit3), 8);
    expect(journalSectionForKey(LogicalKeyboardKey.keyO), 7);
    expect(journalSectionForKey(LogicalKeyboardKey.keyW), isNull);
    expect(JournalSection.fromId(11), isNull);
    expect(
      journalNavigationHelp,
      contains(
        'Alt+1 Organisation, Alt+2 People, Alt+3 Network, Alt+4 Bases, '
        'Alt+5 Ledger, Alt+6 Justice, Alt+7 Agenda, Alt+8 Newspaper, '
        'Alt+9 Reports, Alt+0 City maps and Alt+O Options. ',
      ),
    );
  });

  for (final section in [
    JournalSection.ledger,
    JournalSection.justice,
    JournalSection.agenda,
    JournalSection.newspaper,
  ]) {
    test('${section.label} returns only after the busy command ends at HQ', () {
      final state = JournalNavigationState(
        screen: 'headquarters',
        hasCrew: true,
      );
      state.beginSection(section);
      state.observeReader(
        screen: 'chapter',
        hasCrew: true,
        controllerBusy: true,
      );
      state.finishSection();
      state.observeController(atHeadquarters: false, busy: true);
      state.observeReader(
        screen: 'headquarters',
        hasCrew: true,
        controllerBusy: true,
      );
      expect(state.section, section);
      // No later reader revision: completion alone must settle the return.
      expect(
        state.observeController(atHeadquarters: true, busy: false),
        isTrue,
      );
      expect(state.section, JournalSection.organisation);
      expect(
        state.observeController(atHeadquarters: true, busy: false),
        isFalse,
      );
    });
  }

  test('a deferred return survives intervening required monthly readers', () {
    final state = JournalNavigationState(screen: 'headquarters', hasCrew: true);
    state.beginSection(JournalSection.newspaper);
    state.observeReader(screen: 'media', hasCrew: true, controllerBusy: true);
    state.finishSection();
    state.observeController(atHeadquarters: false, busy: true);
    state.observeReader(
      screen: 'headquarters',
      hasCrew: true,
      controllerBusy: true,
    );
    state.observeReader(screen: 'funding', hasCrew: true, controllerBusy: true);
    expect(state.observeController(atHeadquarters: false, busy: false), isTrue);
    expect(state.section, JournalSection.newspaper);
    // The report has control until its own original acknowledgement returns.
    state.observeReader(
      screen: 'headquarters',
      hasCrew: true,
      controllerBusy: false,
    );
    expect(state.section, JournalSection.organisation);
  });

  for (final section in [
    JournalSection.organisation,
    JournalSection.people,
    JournalSection.network,
    JournalSection.bases,
    JournalSection.reports,
    JournalSection.cityMaps,
    JournalSection.options,
  ]) {
    test('${section.label} retains selection after nested readers return', () {
      final state = JournalNavigationState(
        screen: 'headquarters',
        hasCrew: true,
      );
      state.beginSection(section);
      state.finishSection();
      state.observeController(atHeadquarters: true, busy: true);
      state.observeReader(
        screen: 'planning',
        hasCrew: true,
        controllerBusy: true,
      );
      state.observeReader(
        screen: 'headquarters',
        hasCrew: true,
        controllerBusy: true,
      );
      state.observeController(atHeadquarters: true, busy: false);
      expect(state.section, section);
    });
  }

  test(
    'explicit chapter navigation owns intermediate HQ and rejects reentry',
    () {
      final state = JournalNavigationState(screen: 'media', hasCrew: true);
      expect(state.beginSection(JournalSection.agenda), isTrue);
      expect(state.beginSection(JournalSection.options), isFalse);
      state.observeReader(
        screen: 'headquarters',
        hasCrew: true,
        controllerBusy: true,
      );
      state.observeController(atHeadquarters: true, busy: false);
      expect(state.section, JournalSection.agenda);
      state.observeReader(
        screen: 'agenda',
        hasCrew: true,
        controllerBusy: false,
      );
      state.finishSection();
      expect(state.openingSection, isFalse);
      expect(state.section, JournalSection.agenda);
      state.observeReader(
        screen: 'headquarters',
        hasCrew: true,
        controllerBusy: false,
      );
      expect(state.section, JournalSection.organisation);
    },
  );

  test(
    'session starts at staffed HQ, survives field readers and ends at title',
    () {
      final state = JournalNavigationState(screen: 'generic', hasCrew: true);
      expect(state.active, isFalse);
      state.observeReader(
        screen: 'headquarters',
        hasCrew: false,
        controllerBusy: false,
      );
      expect(state.active, isFalse);
      state.observeReader(
        screen: 'headquarters',
        hasCrew: true,
        controllerBusy: false,
      );
      expect(state.active, isTrue);
      state.observeReader(
        screen: 'tactical',
        hasCrew: true,
        controllerBusy: false,
      );
      expect(state.active, isTrue);
      state.observeReader(
        screen: 'title',
        hasCrew: true,
        controllerBusy: false,
      );
      expect(state.active, isFalse);
      expect(
        JournalNavigationState(screen: 'headquarters', hasCrew: true).active,
        isTrue,
      );
    },
  );
}
