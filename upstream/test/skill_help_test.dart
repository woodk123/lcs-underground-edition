import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test('descriptions expose actual cap/XP and distinguish combat dice', () {
    final actor = game.pool.first;
    actor.rawSkill[Skill.writing] = 5;
    actor.rawSkillXP[Skill.writing] = 23;
    final writing = skillHelp(Skill.writing, actor: actor);
    expect(writing, contains('7–17'));
    expect(writing, contains('Fixed-roll total: 12'));
    expect(writing, contains('XP: 23/150'));
    expect(writing, contains('Intelligence ${actor.skillCap(Skill.writing)}'));
    final firearms = skillHelp(Skill.firearms, actor: actor);
    expect(firearms, contains('Physical attack baseline: d20'));
    expect(firearms, isNot(contains('Current default total')));
    final dodge = skillHelp(Skill.dodge, actor: actor);
    expect(dodge, contains('Combat defense baseline: ranged = Dodge + 10'));
  });

  test(
    'all skill previews preserve the complete campaign and random stream',
    () {
      final actor = game.pool.first;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 67341);
      final expected = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 67341);
      for (final skill in Skill.values) {
        expect(skillHelp(skill, actor: actor), contains(skill.description));
        expect(skillHelp(skill, actor: actor), contains('Training cap:'));
        expect(skillHelp(skill), contains('Useful for:'));
      }
      for (final attribute in Attribute.values) {
        final value = actor.attribute(attribute);
        final help = attributeHelp(attribute, actor: actor);
        expect(help, contains('Default total: ${value - 3}–${value + 7}'));
        expect(help, contains('Fixed-roll total: ${value + 2}'));
        for (final skill in Skill.values.where(
          (s) => s.attribute == attribute,
        )) {
          expect(help, contains(skill.displayName));
        }
        expect(attributeHelp(attribute), contains('Ordinary checks:'));
      }
      expect(List.generate(12, (_) => lcsRandom(100000)), expected);
      expect(jsonEncode(game.gameState.toJson()), before);
    },
  );

  testWidgets('real mouse hover shows mechanics without consuming game input', (
    tester,
  ) async {
    final actor = game.pool.first;
    int? received;
    final reader = engine.getKey().then((key) => received = key);
    final before = jsonEncode(game.gameState.toJson());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SkillTooltip(
              skill: Skill.firearms,
              actor: actor,
              child: const Text('Firearms'),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Firearms')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text(skillHelp(Skill.firearms, actor: actor)), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(engine.console.awaitingInput, isTrue);
    expect(received, isNull);
    expect(jsonEncode(game.gameState.toJson()), before);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    engine.console.sendInput('Enter');
    await tester.pump();
    await reader;
  });

  testWidgets('150% hints fit the window and pass clicks to the page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final actor = game.pool.first;
    final help = skillHelp(Skill.firearms, actor: actor);
    for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
      tester.view.physicalSize = size;
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            tooltipTheme: const TooltipThemeData(
              textStyle: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => clicks++,
              child: Center(
                child: SkillTooltip(
                  skill: Skill.firearms,
                  actor: actor,
                  child: const Text('Firearms'),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Firearms')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.text(help));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      await tester.tapAt(bounds.center);
      await tester.pump();
      expect(
        clicks,
        1,
        reason: 'A hover hint must not intercept page actions.',
      );
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
