import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/operation_record.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'crew_dossier_test.dart' show chooseTab, mountInspector;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader(JournalPalette.serif)
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
  });

  for (final layout in [
    (const Size(1280, 800), 1.0),
    (const Size(800, 600), 1.5),
    (const Size(360, 640), 2.0),
  ]) {
    testWidgets(
      'legal summary and history preserve reader/state across revisits $layout',
      (tester) async {
        final person = game.squad.first;
        person.wantedForCrimes.updateAll((_, _) => 0);
        person.wantedForCrimes[Crime.theft] = 5;
        person.wantedForCrimes[Crime.breakingAndEntering] = 1;
        person.heat = 0;
        person.operationHistory.add(
          OperationRecord(
            date: DateTime(2023, 1, 14),
            siteName: 'Prepared insurance operation',
            outcome: OperationOutcome.returned,
            heatBefore: 0,
            heatAfter: 0,
            participants: [person.name, 'Another participant'],
            juiceChange: 50,
            newCharges: {Crime.theft: 1},
            trainingXp: {Skill.security: 20},
            injuries: ['Torso: bruised'],
            squadResults: ['Carried out: Insurance Fraud Evidence ×1.'],
          ),
        );
        final before = jsonEncode(game.gameState);
        var completed = false;
        final pending = engine.getKey().then((_) => completed = true);
        reseedRNG(seed: 20261018);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 20261018);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.$1;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: buildModernTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(layout.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: CrewInspector(person: person, onClose: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .text('Wanted for: Theft ×5 · Breaking and Entering ×1')
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Personal heat: 0').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('crew-inspector-full')));
        await tester.pumpAndSettle();
        await chooseTab(tester, 2);
        final entry = find.text('Prepared insurance operation');
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(
          find.text('New wanted counts at the time: Theft ×1'),
          findsOneWidget,
        );
        expect(find.text('Security: +20 training XP'), findsOneWidget);
        expect(find.text('Injury at return: Torso: bruised'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Carried out: Insurance Fraud Evidence ×1.'),
        );
        final scrolled = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('crew-dossier-scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels;
        expect(scrolled, greaterThan(0));
        await chooseTab(tester, 1);
        await chooseTab(tester, 2);
        await tester.ensureVisible(entry);
        expect(find.text('Prepared insurance operation'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CrewDossier), findsNothing);
        await tester.tap(find.byKey(const ValueKey('crew-inspector-full')));
        await tester.pumpAndSettle();
        await chooseTab(tester, 2);
        await tester.ensureVisible(entry);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(completed, isFalse);
        expect(engine.console.awaitingInput, isTrue);
        expect(jsonEncode(game.gameState), before);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
        engine.console.sendInput('Enter');
        await pending;
      },
    );
  }

  testWidgets('older campaigns explain the absence of reconstructed history', (
    tester,
  ) async {
    await mountInspector(tester, game.pool.first);
    await chooseTab(tester, 2);
    expect(
      find.textContaining('earlier events are not reconstructed'),
      findsOneWidget,
    );
  });
}
