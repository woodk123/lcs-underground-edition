import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    clearScreenOnNextMessage = false;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = game.squad[1];
  });

  Future<int> headquartersReader() {
    engine.erase();
    final location = game.activeSquad?.site ?? game.activeSafehouse;
    baseModeSquadSafehouseDisplay(location);
    baseModeOptionsDisplay(location);
    return engine.getKey();
  }

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    journalReadingScale.value = 1.5;
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
    testWidgets(
      'processing buffers wait for the next source reader at $size / 150%',
      (tester) async {
        final hqReader = headquartersReader();
        await mount(tester, size);
        final journal = find.byType(OrganisationJournal);
        final journalState = tester.state<OrganisationJournalState>(journal);
        final footerAction = find.byKey(const ValueKey('journal-advance-day'));
        final footerPosition = tester.getRect(footerAction).bottomRight;
        final controller = tester
            .widget<OrganisationJournal>(journal)
            .controller;
        controller.inspectPerson(game.squad[1].id);
        await tester.pumpAndSettle();
        final personId = controller.selectedPersonId;
        expect(personId, game.squad[1].id);
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 5167);
        final nextRandom = lcsRandom(100000);
        reseedRNG(seed: 5167);

        // Finish the actual source HQ reader. A day handler can then erase and
        // paint a transient generated map without asking for any input yet.
        engine.console.sendInput('w');
        expect(await hqReader, engine.Key.w);
        engine.erase();
        engine.mvaddstr(0, 0, 'TRANSIENT FOREST MAP');
        engine.mvaddstr(11, 0, '↑ ♠ ↑ ♣ ↑ ♠ ↑ ♣');
        engine.mvaddstr(12, 0, '♣ ↑ ♠ ↑ ♣ ↑ ♠ ↑');
        engine.console.flush();
        await tester.pumpAndSettle();
        expect(engine.console.screen, 'generic');
        expect(engine.console.awaitingInput, isFalse);
        expect(engine.console.actions, isEmpty);
        expect(
          find.byKey(const ValueKey('journal-processing')),
          findsOneWidget,
        );
        expect(find.text('Preparing the next report'), findsOneWidget);
        expect(
          find.textContaining('TRANSIENT FOREST MAP', findRichText: true),
          findsNothing,
        );
        expect(find.textContaining('↑ ♠', findRichText: true), findsNothing);
        expect(find.text('Continue'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('journal-advance-day')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('journal-save-exit')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester.state<OrganisationJournalState>(journal),
          same(journalState),
        );
        expect(controller.selectedPersonId, personId);
        expect(engine.console.sendInput('Enter'), isFalse);
        expect(jsonEncode(game.gameState.toJson()), before);

        // The next actual notice owns an any-key reader and must replace the
        // progress note immediately, even with the transient map still painted.
        final report = showMessage(
          'The current source report is ready.',
          title: 'Daily report',
        );
        await tester.pumpAndSettle();
        expect(engine.console.awaitingInput, isTrue);
        expect(find.byKey(const ValueKey('journal-processing')), findsNothing);
        expect(find.text('Daily report'), findsOneWidget);
        expect(
          find.text('The current source report is ready.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('TRANSIENT FOREST MAP', findRichText: true),
          findsNothing,
        );
        expect(find.text('Continue').hitTestable(), findsOneWidget);
        expect(tester.getRect(footerAction).bottomRight, footerPosition);
        expect(
          find.descendant(of: footerAction, matching: find.text('Continue')),
          findsOneWidget,
        );
        final staleContinue = tester
            .widget<FilledButton>(footerAction)
            .onPressed!;
        await tester.tap(footerAction);
        await tester.pump();
        await report;
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(controller.selectedPersonId, personId);

        // A plain generic awaited prompt with no actions is also a real reader.
        // It must remain visible and retain its original any-key reader.
        engine.erase();
        engine.mvaddstr(9, 1, 'An original awaited question.');
        final plainReader = engine.getKey();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('journal-processing')), findsNothing);
        expect(
          find.textContaining(
            'An original awaited question.',
            findRichText: true,
          ),
          findsWidgets,
        );
        expect(engine.console.awaitingInput, isTrue);
        expect(engine.console.sendInput('Enter'), isTrue);
        await tester.pump();
        expect(await plainReader, engine.Key.enter);

        // Explicit Continue choices keep their actual source key and disabled
        // state. A decision with no Continue must still be answered in-page.
        engine.erase();
        engine.addOptionText(24, 0, 'c', 'C - Continue', enabledWhen: false);
        final continueReader = engine.getKey();
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(footerAction).onPressed, isNull);
        engine.addOptionText(24, 0, 'c', 'C - Continue');
        engine.console.flush();
        await tester.pumpAndSettle();
        await tester.tap(footerAction);
        await tester.pump();
        expect(await continueReader, engine.Key.c);

        engine.erase();
        engine.addOptionText(7, 0, 'a', 'A - Choose a response');
        final decisionReader = engine.getKey();
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(footerAction).onPressed, isNull);
        engine.console.sendInput('a');
        await decisionReader;

        final returned = headquartersReader();
        await tester.pumpAndSettle();
        staleContinue();
        expect(engine.console.awaitingInput, isTrue);
        expect(
          tester.state<OrganisationJournalState>(journal),
          same(journalState),
        );
        expect(controller.selectedPersonId, personId);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(lcsRandom(100000), nextRandom);
        engine.console.sendInput('Enter');
        await returned;
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
