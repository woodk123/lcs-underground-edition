import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_crew_roster.dart';

void main() {
  for (final width in [300.0, 520.0]) {
    testWidgets('roster names and exceptions remain readable at $width', (
      tester,
    ) async {
      var selections = 0;
      var inspections = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 300 ? 1.5 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: OrganisationCrewMemberView(
                  data: const OrganisationCrewMemberData(
                    personId: 7,
                    name: 'Eugene Kaltenbrunner',
                    selected: true,
                    orderDescription: 'Practice Science',
                    location: 'Holmes, SEA',
                    clothingSummary: 'Bloodstained clothes',
                    clothingWarning: true,
                    skillSummary: 'Science 10 · Persuasion 8 · Street Smarts 7',
                    weaponSummary: 'AK-102 Rifle · 30 rounds loaded',
                    hasAssignment: true,
                    numberKey: '2',
                    injury: (
                      label: 'Very low blood',
                      details: '30/140 blood',
                      urgent: true,
                    ),
                  ),
                  showingOrders: true,
                  stacked: width == 300,
                  allocating: false,
                  juiceBadge: const Text('Juice 0'),
                  onSelect: () => selections++,
                  onInspect: () => inspections++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('journal-member-name:7'));
      final assignment = find.byKey(const ValueKey('journal-member-order:7'));
      expect(tester.getTopLeft(assignment).dx, tester.getTopLeft(name).dx);
      expect(
        tester.getTopLeft(assignment).dy,
        greaterThan(tester.getBottomLeft(name).dy - 1),
      );
      final skills = find.byKey(const ValueKey('journal-member-skills:7'));
      final weapon = find.byKey(const ValueKey('journal-member-weapon:7'));
      final clothes = find.byKey(const ValueKey('journal-member-clothing:7'));
      for (final label in [
        name,
        find.text('Very low blood'),
        assignment,
        skills,
        weapon,
        clothes,
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, false);
      }
      expect(find.text('Clothes: Bloodstained clothes'), findsOneWidget);
      expect(
        find.text('Weapon: AK-102 Rifle · 30 rounds loaded'),
        findsOneWidget,
      );
      expect(
        find.text('Top skills: Science 10 · Persuasion 8 · Street Smarts 7'),
        findsOneWidget,
      );
      expect(find.byTooltip('30/140 blood'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('journal-member:7')));
      await tester.tap(find.byKey(const ValueKey('hq-dossier:7')));
      expect(selections, 1);
      expect(inspections, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
