import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/aging.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/recruitment_target_picker.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test('age explanations match body calculations at every band boundary', () {
    final person = game.pool.first..body = HumanoidBody();
    for (final age in [5, 10, 11, 15, 16, 34, 35, 51, 52, 69, 70, 90]) {
      person.birthDate = DateTime(game.gameState.date.year - age);
      for (final attribute in Attribute.values) {
        const raw = 20;
        final result = person.body.permanentAttributeMods(attribute, raw, age);
        final description = ageAttributeEffect(person, attribute);
        if (attribute == Attribute.strength && age < childAge) {
          expect(result, raw ~/ 2);
          expect(description, 'Strength ×½ (rounded)');
          expect(description, isNot(contains('-3')));
        } else {
          final modifier = ageModifierForAttribute(attribute, age);
          expect(result, raw + modifier);
          expect(
            description,
            endsWith(
              modifier == 0
                  ? 'unchanged'
                  : '${modifier > 0 ? '+' : ''}$modifier',
            ),
          );
        }
      }
    }
    person.body = TankBody();
    expect(ageAttributeSummary(person), contains('No age attribute modifiers'));
    expect(ageAttributeEffect(person, Attribute.strength), 'No age modifier');
  });

  test('55-year-old modifiers, Health risks and next band are explicit', () {
    final person = game.pool.first
      ..body = HumanoidBody()
      ..birthDate = DateTime(game.gameState.date.year - 55);
    expect(
      ageAttributeSummary(person),
      'Strength -3 · Agility -3 · Intelligence +2 · Charisma +2 · Wisdom +1',
    );
    expect(ageHelp(person), contains('Next attribute age band at 70'));
    expect(ageHelp(person), contains('no old-age Health-loss roll'));
    expect(ageHelp(person), contains('birthdays do not award skill points'));
    expect(
      attributeHelp(Attribute.heart, actor: person),
      contains('Heart unchanged'),
    );
    for (final entry in {60: 0, 61: 1, 65: 1, 66: 2, 70: 2, 71: 3}.entries) {
      person.birthDate = DateTime(game.gameState.date.year - entry.key);
      if (entry.value == 0) {
        expect(ageHelp(person), contains('no old-age Health-loss roll'));
      } else {
        expect(ageHelp(person), contains('${entry.value} independent'));
        expect(ageHelp(person), contains('1 in 1,825'));
      }
    }
  });

  test(
    'profession previews explain only age bands in their generation range',
    () {
      final type = creatureTypes['CREATURE_PROGRAMMER']!;
      expect(
        recruitmentProfessionHelp(type),
        contains('Age modifiers by generated age'),
      );
      final range = ageRangeHelp((34, 52));
      expect(range, contains('34: No age attribute modifiers.'));
      expect(range, contains('35–51: Strength -1'));
      expect(range, contains('52: Strength -3'));
      expect(range, isNot(contains('70')));
    },
  );

  for (final layout in [
    (1280.0, 800.0, 1.0),
    (800.0, 600.0, 1.5),
    (360.0, 640.0, 2.0),
  ]) {
    testWidgets(
      'age details expand by keyboard and stay read-only at $layout',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(layout.$1, layout.$2);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final person = game.pool.first
          ..body = HumanoidBody()
          ..birthDate = DateTime(game.gameState.date.year - 55);
        final before = jsonEncode(game.gameState);
        engine.console.addstr('Pending gameplay prompt');
        final revision = engine.console.revision.value;
        reseedRNG(seed: 720131);
        final expected = List.generate(10, (_) => lcsRandom(100000));
        reseedRNG(seed: 720131);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildJournalTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(layout.$3)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(child: AgeEffects(person: person)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Age modifiers: Strength -3'),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Starting skills: generated'),
          findsOneWidget,
        );
        await tester.tap(find.text('How age affects this character'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Starting skills: generated'), findsNothing);
        expect(jsonEncode(game.gameState), before);
        expect(engine.console.revision.value, revision);
        expect(List.generate(10, (_) => lcsRandom(100000)), expected);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
