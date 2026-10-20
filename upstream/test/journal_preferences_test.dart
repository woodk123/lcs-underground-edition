import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/game_options.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    journalPresentation.value = const JournalPreferenceValues();
    journalReadingScale.value = 1;
    game.gameState = game.GameState();
    engine.console = Console();
  });

  tearDown(() {
    journalPresentation.value = const JournalPreferenceValues();
    journalReadingScale.value = 1;
  });

  test(
    'older preferences keep comfortable layout and explanatory guidance',
    () async {
      SharedPreferences.setMockInitialValues({'fontSize': 20.0});
      final options = GameOptions();
      await options.load();
      expect(options.journalCompact, isFalse);
      expect(options.journalGuidance, isTrue);
      expect(options.fontSize, 20);
    },
  );

  test(
    'presentation persistence preserves reading and campaign options',
    () async {
      SharedPreferences.setMockInitialValues({
        'journalReadingScale': 1.5,
        'fontSize': 20.0,
        'lighterTone': true,
      });
      final options = GameOptions();
      await options.load();
      options.journalCompact = true;
      options.journalGuidance = false;
      await options.saveJournalPresentation();
      final later = GameOptions();
      await later.load();
      expect(later.journalCompact, isTrue);
      expect(later.journalGuidance, isFalse);
      expect(later.journalScale, 1.5);
      expect(later.fontSize, 20);
      expect(later.lighterTone, isTrue);
    },
  );

  for (final reading in [1.0, 1.5]) {
    testWidgets(
      'preferences preserve pending commands, state, RNG and reading at $reading',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        journalReadingScale.value = reading;
        engine.mvaddstr(0, 0, 'Choose the next action');
        engine.addOptionText(5, 0, 'a', 'A - Keep the current action');
        String? received;
        unawaited(engine.console.getkey().then((value) => received = value));
        await tester.pumpWidget(const MainApp());
        await tester.pumpAndSettle();
        final before = jsonEncode(game.gameState.toJson());
        final revision = engine.console.revision.value;
        reseedRNG(seed: 20261020);
        final expectedRoll = lcsRandom(1000000);
        reseedRNG(seed: 20261020);

        await tester.tap(find.byTooltip('Interface preferences'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('journal-layout-compact')),
        );
        await tester.tap(find.byKey(const ValueKey('journal-layout-compact')));
        await tester.pumpAndSettle();
        final guidance = find.byKey(const ValueKey('journal-show-guidance'));
        await tester.ensureVisible(guidance);
        await tester.tap(guidance);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
        await tester.pump();
        expect(
          received,
          isNull,
          reason: 'Dialog keys must not issue game commands.',
        );
        expect(journalPresentation.value.compact, isTrue);
        expect(journalPresentation.value.showGuidance, isFalse);
        expect(journalReadingScale.value, reading);
        expect(engine.console.revision.value, revision);
        expect(engine.console.awaitingInput, isTrue);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(lcsRandom(1000000), expectedRoll);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
        await tester.pump(const Duration(milliseconds: 20));
        expect(received, 'a');
        final later = GameOptions();
        await later.load();
        expect(later.journalCompact, isTrue);
        expect(later.journalGuidance, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('interface dialog retains an unfinished edited name', (
    tester,
  ) async {
    engine.console.screen = 'title';
    engine.addOptionText(5, 0, 'n', 'N - Start a New Game');
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    engine.erase();
    engine.mvaddstr(0, 0, 'Your name');
    final pendingName = engine.mvgetstr(2, 0, starting: 'Alice');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('A small movement. A long game.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.tap(find.byTooltip('Interface preferences'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Avery',
    );
    expect(engine.console.textInputValue, 'Alice');
    tester.testTextInput.enterText('Avery Fox');
    await tester.pump();
    await tester.tap(find.text('Confirm text'));
    await tester.pumpAndSettle();
    expect(await pendingName, 'Avery Fox');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Tab away from a name never types into its hidden source reader',
    (tester) async {
      engine.console.screen = 'title';
      engine.addOptionText(5, 0, 'n', 'N - Start a New Game');
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      engine.erase();
      engine.mvaddstr(0, 0, 'Your name');
      final pendingName = engine.mvgetstr(2, 0, starting: 'Alice');
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, 'Avery');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.pump(const Duration(milliseconds: 20));
      expect(engine.console.textInputValue, 'Alice');
      expect(tester.widget<TextField>(field).controller!.text, 'Avery');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await pendingName, 'Avery');
      expect(tester.takeException(), isNull);
    },
  );
}
