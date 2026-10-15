import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each illustrated task maps by its exact original activity enum', () {
    const examples = [
      ActivityType.donations,
      ActivityType.sellArt,
      ActivityType.makeClothing,
      ActivityType.sellMusic,
      ActivityType.recruiting,
      ActivityType.study,
      ActivityType.teachLiberalArts,
      ActivityType.clinic,
      ActivityType.graffiti,
      ActivityType.trouble,
      ActivityType.writeGuardian,
      ActivityType.hacking,
      ActivityType.stealCars,
      ActivityType.interrogation,
      ActivityType.bury,
      ActivityType.none,
    ];
    for (var i = 0; i < examples.length; i++) {
      expect(journalOrderIconIndex(examples[i]), i);
    }
    expect(journalOrderIconIndex(ActivityType.wheelchair), 20);
    expect(journalOrderIconIndex(ActivityType.streamGuardian), 21);
    expect(journalOrderIconIndex(ActivityType.ccfraud), 19);
    expect(journalOrderIconIndex(ActivityType.sleeperSpy), 22);
    expect(journalOrderIconIndex(ActivityType.takeClass), 5);
    expect(journalOrderIconIndex(ActivityType.teachFighting), 6);
    expect(journalOrderIconIndex(ActivityType.teachCovert), 6);
    expect(journalOrderIconIndex(ActivityType.sleeperRecruit), 4);
  });

  test(
    'every inspected crop is inside the offline transparent atlas',
    () async {
      final bytes = await rootBundle.load(journalOrderIconAsset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      expect(image.width, 1254);
      expect(image.height, 1254);
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      for (final rect in journalOrderIconSourceRects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(image.width));
        expect(rect.bottom, lessThanOrEqualTo(image.height));
        var visible = 0;
        var transparent = 0;
        for (var y = rect.top.toInt(); y < rect.bottom; y += 5) {
          for (var x = rect.left.toInt(); x < rect.right; x += 5) {
            final alpha = pixels!.getUint8((y * image.width + x) * 4 + 3);
            if (alpha > 32) visible++;
            if (alpha == 0) transparent++;
          }
        }
        expect(visible, greaterThan(100));
        expect(transparent, greaterThan(20));
      }
      image.dispose();
    },
  );

  testWidgets(
    'order paintings neither block controls nor add navigation stops',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TextButton(
                      onPressed: () => count++,
                      child: const Text('Prepare'),
                    ),
                    const Center(
                      child: JournalOrderIcon(type: ActivityType.donations),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare'));
      expect(count, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'companion paintings have transparent margins and complete source crops',
    () async {
      final bytes = await rootBundle.load(journalExtraOrderIconAsset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(journalExtraOrderIconSourceRects, hasLength(12));
      for (final rect in journalExtraOrderIconSourceRects) {
        expect(rect.right, lessThanOrEqualTo(image.width));
        expect(rect.bottom, lessThanOrEqualTo(image.height));
        var visible = 0;
        var clear = 0;
        for (var y = rect.top.toInt(); y < rect.bottom; y += 4) {
          for (var x = rect.left.toInt(); x < rect.right; x += 4) {
            final alpha = pixels.getUint8((y * image.width + x) * 4 + 3);
            if (alpha > 64) visible++;
            if (alpha == 0) clear++;
          }
        }
        expect(visible, greaterThan(500));
        expect(clear, greaterThan(20));
      }
      image.dispose();
    },
  );

  testWidgets('every original activity has a decorative painting or fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: Wrap(
            children: [
              for (final type in ActivityType.values)
                JournalOrderIcon(type: type, size: 32),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(JournalOrderIcon),
      findsNWidgets(ActivityType.values.length),
    );
    expect(tester.takeException(), isNull);
  });
}
