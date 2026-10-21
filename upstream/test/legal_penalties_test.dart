import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/legal_penalties.dart';
import 'package:lcs_new_age/modern/legal_status.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    for (final (family, asset) in [
      (JournalPalette.serif, 'fonts/journal/LibreBaskerville-Variable.ttf'),
      ('ModernSans', 'fonts/modern/roboto-regular.ttf'),
      ('Roboto', 'fonts/modern/roboto-regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.pool.first.wantedForCrimes.updateAll((_, _) => 0);
    game.laws[Law.deathPenalty] = DeepAlignment.eliteLiberal;
  });

  test('current counts multiply inclusive base ranges and cap at ten', () {
    final person = game.pool.first;
    person.wantedForCrimes[Crime.theft] = 5;
    person.wantedForCrimes[Crime.breakingAndEntering] = 1;
    expect(possiblePenalties(person), contains('Theft ×5: 5–20 months'));
    expect(
      possiblePenalties(person),
      contains('Breaking and Entering ×1: 1 month'),
    );
    expect(
      possiblePenalties(person),
      contains('Combined base time: 6–21 months'),
    );
    person.wantedForCrimes[Crime.theft] = 15;
    expect(
      possiblePenalties(person),
      contains('Theft ×15: 10–40 months (10 counts used)'),
    );
    expect(
      possiblePenalties(person),
      contains('Combined base time: 11–41 months'),
    );
    person.wantedForCrimes.updateAll((_, _) => 0);
    expect(possiblePenalties(person), 'No current wanted charges.');
  });

  test(
    'law-dependent, life and zero-time charges reflect sentencing rules',
    () {
      final person = game.pool.first;
      person.wantedForCrimes[Crime.drugDistribution] = 2;
      person.wantedForCrimes[Crime.flagBurning] = 1;
      const drugRanges = ['6–724', '6–244', '6–28'];
      for (final law in DeepAlignment.values) {
        game.laws[Law.drugs] = law;
        game.laws[Law.flagBurning] = law;
        final help = possiblePenalties(person);
        if (law.index < 3) {
          expect(
            help,
            contains('Drug Distribution ×2: ${drugRanges[law.index]} months'),
          );
        } else {
          expect(help, contains('Drug Distribution ×2: no added prison time'));
        }
        if (law == DeepAlignment.archConservative) {
          expect(help, contains('120–360 months or 1 life term'));
          expect(help, isNot(contains('Combined base time')));
        }
      }
      person.wantedForCrimes.updateAll((_, _) => 0);
      person.wantedForCrimes[Crime.murder] = 3;
      expect(possiblePenalties(person), contains('Murder ×3: 3 life terms'));
      person.wantedForCrimes[Crime.murder] = 1;
      expect(
        possiblePenalties(person),
        contains('120–360 months or 1 life term'),
      );
      game.laws[Law.deathPenalty] = DeepAlignment.moderate;
      expect(
        possiblePenalties(person),
        contains('allows execution without leniency'),
      );
      person.wantedForCrimes.updateAll((_, _) => 0);
      person.wantedForCrimes[Crime.cyberVandalism] = 1;
      expect(
        possiblePenalties(person),
        contains('Digital Vandalism ×1: no added prison time'),
      );
      expect(possiblePenalties(person), isNot(contains('execution')));
      game.laws[Law.deathPenalty] = DeepAlignment.archConservative;
      expect(possiblePenalties(person), contains('execution'));
    },
  );

  test(
    'every offence and law can be inspected without changing campaign or RNG',
    () {
      final person = game.pool.first;
      for (final crime in Crime.values) {
        person.wantedForCrimes[crime] = 14;
      }
      for (final law in DeepAlignment.values) {
        game.laws[Law.drugs] = law;
        game.laws[Law.flagBurning] = law;
        game.laws[Law.deathPenalty] = law;
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 7842);
        final expected = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 7842);
        final help = possiblePenalties(person);
        for (final crime in Crime.values) {
          expect(help, contains('${crime.wantedFor} ×14:'));
        }
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(List.generate(12, (_) => lcsRandom(100000)), expected);
      }
    },
  );

  testWidgets(
    'hover, tap, keyboard, dismissal and revisiting preserve the reader',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final person = game.pool.first;
      person.wantedForCrimes[Crime.theft] = 5;
      person.wantedForCrimes[Crime.breakingAndEntering] = 1;
      final before = jsonEncode(game.gameState.toJson());
      int? received;
      final reader = engine.getKey().then((value) => received = value);
      for (final (size, scale) in [
        (const Size(1280, 800), 1.0),
        (const Size(800, 600), 1.5),
        (const Size(390, 844), 2.0),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LegalStatusSummary(person: person),
              ),
            ),
          ),
        );
        final button = find.widgetWithText(TextButton, 'Possible penalties');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        final help = find.text(possiblePenalties(person));
        expect(help, findsOneWidget, reason: 'hover at $size / $scale');
        final bounds = tester.getRect(
          find.byKey(const ValueKey('possible-penalties-scroll')),
        );
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
        await mouse.removePointer();
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(help, findsOneWidget);
        Focus.of(
          tester.element(find.text('Possible penalties')),
        ).requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(help, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(help, findsOneWidget);
        expect(received, isNull);
        expect(engine.console.awaitingInput, isTrue);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      engine.console.sendInput('Enter');
      await tester.pump();
      await reader;
    },
  );

  testWidgets(
    'inspector and dossier retain penalties through close and revisit',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final person = game.pool.first;
      person.wantedForCrimes[Crime.theft] = 5;
      person.wantedForCrimes[Crime.breakingAndEntering] = 1;
      final before = jsonEncode(game.gameState.toJson());
      for (final (size, scale) in [
        (const Size(1280, 800), 1.0),
        (const Size(800, 600), 1.5),
        (const Size(390, 844), 2.0),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('legal-capture'),
            child: MaterialApp(
              theme: buildJournalTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextButton(
                        onPressed: () =>
                            showCrewDossier(context, person: person),
                        child: const Text('Open dossier'),
                      ),
                      Expanded(
                        child: CrewInspector(person: person, onClose: () {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final penaltyButton = find.widgetWithText(
          TextButton,
          'Possible penalties',
        );
        await tester.ensureVisible(penaltyButton);
        await tester.tap(penaltyButton);
        await tester.pumpAndSettle();
        expect(find.text(possiblePenalties(person)), findsOneWidget);
        if (Platform.environment['LCS_CAPTURE_SCREENS'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('legal-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final output = File(
              '../reports/legal-penalties/inspector-${size.width.toInt()}-${(scale * 100).toInt()}.png',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open dossier'));
        await tester.pumpAndSettle();
        for (final tab in [2, 1, 2]) {
          final target = find.byKey(ValueKey('crew-dossier-tab-$tab'));
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
        final dossierButton = find.descendant(
          of: find.byType(Dialog),
          matching: penaltyButton,
        );
        await tester.ensureVisible(dossierButton);
        await tester.tap(dossierButton);
        await tester.pumpAndSettle();
        expect(find.text(possiblePenalties(person)), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byType(Dialog),
          findsOneWidget,
          reason: 'Escape first dismisses penalties',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
