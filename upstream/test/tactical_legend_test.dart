import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_legend.dart';

void main() {
  for (final size in [const Size(320, 480), const Size(560, 500)]) {
    testWidgets('complete map key scrolls and dismisses at $size and 150%', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.5),
            ),
            child: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: FieldPlanLegend(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('field-plan-key-open')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('field-plan-key-dialog'));
      expect(dialog, findsOneWidget);
      for (final label in [
        'Your squad',
        'Door',
        'Locked door',
        'Cannot unlock door',
        'Metal door',
        'Burning door',
        'Exit',
        'Stairs up',
        'Stairs down',
        'Siege enemy',
        'Wounded siege enemy',
        'Armored siege enemy',
        'Loot',
        'Point of interest',
        'Restricted area',
        'Fire',
        'Defensive booby trap',
        'Bloodstains',
        'Debris',
        'In view',
        'Previously explored',
        'Unexplored',
      ]) {
        expect(
          find.descendant(of: dialog, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.textContaining('Other people appear in the encounter list'),
        findsOneWidget,
      );
      final unknown = find.descendant(
        of: dialog,
        matching: find.text('Unexplored'),
      );
      await tester.ensureVisible(unknown);
      await tester.pumpAndSettle();
      final scroll = find.byKey(const ValueKey('field-plan-key-scroll'));
      final unknownRect = tester.getRect(unknown);
      final scrollRect = tester.getRect(scroll);
      expect(unknownRect.top, greaterThanOrEqualTo(scrollRect.top));
      expect(unknownRect.bottom, lessThanOrEqualTo(scrollRect.bottom));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('field-plan-key-close')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.text('Map key'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
