import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

double contrast(Color a, Color b) {
  final aa = a.computeLuminance();
  final bb = b.computeLuminance();
  return aa > bb ? (aa + .05) / (bb + .05) : (bb + .05) / (aa + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('body and secondary journal text remain readable on live surfaces', () {
    for (final background in [
      JournalPalette.page,
      JournalPalette.card,
      JournalPalette.inset,
      JournalPalette.selected,
    ]) {
      expect(contrast(JournalPalette.ink, background), greaterThanOrEqualTo(7));
      expect(
        contrast(JournalPalette.muted, background),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(JournalPalette.card, JournalPalette.olive),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
    'journal fonts and license ship with the offline asset bundle',
    () async {
      final regular = await rootBundle.load(
        'fonts/journal/LibreBaskerville-Variable.ttf',
      );
      final italic = await rootBundle.load(
        'fonts/journal/LibreBaskerville-Italic-Variable.ttf',
      );
      final license = await rootBundle.loadString('fonts/journal/OFL.txt');
      expect(regular.lengthInBytes, greaterThan(100000));
      expect(italic.lengthInBytes, greaterThan(100000));
      expect(license, contains('SIL OPEN FONT LICENSE'));
      expect(license, contains('Libre Baskerville'));
    },
  );

  testWidgets('decorative rings never block an overlapping live control', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  JournalSurface(
                    lined: true,
                    child: Center(
                      child: TextButton(
                        onPressed: () => presses++,
                        child: const Text('Select crew'),
                      ),
                    ),
                  ),
                  const Center(
                    child: SizedBox(height: 160, child: JournalBinding()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select crew'));
    expect(presses, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: SizedBox(height: 4, child: JournalBinding())),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
