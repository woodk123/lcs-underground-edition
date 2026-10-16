import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/title_screen/new_game.dart';
import 'package:lcs_new_age/title_screen/world.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Future<void> send(String key) async {
  expect(engine.console.awaitingInput, isTrue);
  expect(engine.console.sendInput(key), isTrue);
  await Future<void>.delayed(Duration.zero);
}

Future<void> beginFounder() async {
  final setup = setupNewGame();
  expect(engine.console.creation?.stage, CreationStage.setup);
  await send('Enter');
  await setup;
  makeWorld();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() => engine.console = Console());

  test('campaign setting cards use the original cycling readers', () async {
    final setup = setupNewGame();
    expect(engine.console.creation?.fields, hasLength(3));
    final initial = engine.console.creation!.fields;
    await send('C');
    expect(engine.console.creation!.fields[2].value, 'Welcome to the Jungle');
    expect(engine.console.creation!.fields[0].value, initial[0].value);
    await send('B');
    expect(
      engine.console.creation!.fields[1].value,
      "We Didn't Start The Fire",
    );
    await send('Enter');
    await setup;
    expect(game.gameState.alternatingInitiative, isTrue);
    expect(game.gameState.ccsAggressive, isTrue);
    engine.console.erase();
    expect(engine.console.creation, isNull);
  });

  for (final fate in [false, true]) {
    test(
      'original ${fate ? 'fate' : 'chosen'} founder flow reaches its name reader',
      () async {
        await beginFounder();
        final creation = makeCharacter();
        expect(engine.console.creation?.stage, CreationStage.identity);
        expect(engine.console.creation!.founder, isNull);
        expect(game.pool, isEmpty);
        final beforeRerolls = jsonEncode(game.gameState.toJson());
        final originalFields = engine.console.creation!.fields
            .map((field) => field.value)
            .toList();
        final originalPortrait = engine.console.creation!.portraitId;
        expect(originalPortrait, isNotNull);
        reseedRNG(seed: 53141);
        final expectedRolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 53141);
        await send('F');
        final firstReroll = engine.console.creation!.portraitId;
        expect(firstReroll, isNot(originalPortrait));
        await send('F');
        final chosenPortrait = engine.console.creation!.portraitId;
        expect(chosenPortrait, isNot(firstReroll));
        expect(
          engine.console.creation!.fields.map((field) => field.value),
          originalFields,
        );
        expect(jsonEncode(game.gameState.toJson()), beforeRerolls);
        expect(List.generate(12, (_) => lcsRandom(100000)), expectedRolls);
        if (fate) await send('D');
        await send('Enter');
        expect(game.pool.first.portraitId, chosenPortrait);
        for (var step = 1; step <= 10; step++) {
          final frame = engine.console.creation!;
          expect(frame.stage, CreationStage.background);
          expect(frame.step, step);
          expect(frame.totalSteps, 10);
          expect(frame.founder, same(game.pool.first));
          if (fate) {
            expect(frame.choices, isEmpty);
            expect(frame.body, hasLength(2));
            await send('Enter');
          } else {
            expect(frame.choices, hasLength(5));
            expect(
              frame.choices.every((choice) => choice.description.isNotEmpty),
              isTrue,
            );
            final agility = game.pool.first.rawAttributes[Attribute.agility]!;
            await send(frame.choices.first.key);
            if (step == 1) {
              expect(game.pool.first.birthDate, DateTime(2004, 6, 30));
              expect(
                game.pool.first.rawAttributes[Attribute.agility],
                agility + 2,
              );
            }
            if (step == 2) expect(game.pool.first.skill(Skill.stealth), 1);
          }
        }
        expect(engine.console.creation?.stage, CreationStage.briefing);
        expect(game.pool.first.portraitId, chosenPortrait);
        expect(engine.console.creation!.body, hasLength(5));
        await send('Enter');
        expect(engine.console.creation?.stage, CreationStage.name);
        expect(engine.console.textInput, isTrue);
        final original = engine.console.textInputValue;
        for (var i = 0; i < original.length; i++) {
          await send('Backspace');
          expect(engine.console.creation?.stage, CreationStage.name);
        }
        for (final char in 'Journal Founder'.split('')) {
          await send(char);
          expect(engine.console.creation?.stage, CreationStage.name);
        }
        await send('Enter');
        await creation;
        expect(game.pool.first.name, 'Journal Founder');
        expect(engine.console.textInput, isFalse);
        expect(engine.console.creation, isNull);
        final loaded = decodeSaveContents(
          encodeSaveContents(
            SaveFile(
              version: '1.5.6',
              gameId: game.gameState.uniqueGameId.toString(),
              saveData: game.gameState.toJson(),
              lastPlayed: null,
            ),
          ),
        );
        expect(loaded.gameState!.lcs.pool.first.portraitId, chosenPortrait);
        expect(
          ensurePortraitId(loaded.gameState!.lcs.pool.first),
          chosenPortrait,
        );
      },
    );
  }

  testWidgets(
    'the journal name page retains the actual text reader and focus',
    (tester) async {
      engine.console.creation = CreationContext(
        stage: CreationStage.name,
        title: 'Sign the founding record',
        prompt: 'What is your name to the people?',
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ModernGameShell())),
      );
      final input = engine.enterName(2, 0, 'Original Founder', prefill: true);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('journal-creation-page')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller!.text, 'Original Founder');
      await tester.enterText(find.byType(TextField), 'New Public Name');
      await tester.tap(find.text('Begin campaign'));
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(await input, 'New Public Name');
      expect(engine.console.textInput, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
