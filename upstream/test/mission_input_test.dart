import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Alignment;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/site_display.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/talk/talk_in_combat.dart';
import 'package:lcs_new_age/talk/talk_outside_combat.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.activeSite = game.squad.first.site;
    game.mode = GameMode.site;
    game.siteAlarm = false;
    game.encounter.clear();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    levelMap[35][11][0].known = true;
    levelMap[36][11][0].known = true;
  });

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
    for (final police in [false, true]) {
      testWidgets(
        'alarmed ${police ? 'police' : 'unarmed occupants'} movement uses the original override at $size',
        (tester) async {
          final opponent =
              Creature.fromId(
                  police
                      ? CreatureTypeIds.cop
                      : CreatureTypeIds.sweatshopWorker,
                )
                ..align = Alignment.conservative
                ..noticedParty = true;
          if (!police) opponent.equippedWeapon = null;
          game.encounter.add(opponent);
          game.siteAlarm = true;
          expect(siteEncounterMovementOverride(), !police);
          siteMovementOptions();
          engine.console.screen = 'tactical';
          final reader = engine.getKey();
          await mount(tester, size);
          final right = tester.widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Move right'),
              matching: find.byType(IconButton),
            ),
          );
          expect(right.onPressed != null, !police);
          expect(
            engine.console.actions
                .where((action) => action.entityType == 'field-direction')
                .every((action) => action.enabled == !police),
            isTrue,
          );
          if (police) {
            engine.console.sendInput('Enter');
            expect(await reader, engine.Key.enter);
          } else {
            await tester.tap(find.byTooltip('Move right'));
            await tester.pump();
            expect(await reader, engine.Key.rightArrow);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('speaker choices retain named skill ratings at $size', (
      tester,
    ) async {
      final person = game.squad.first;
      clearSceneAreas();
      engine.mvaddstr(9, 1, 'Which Liberal will speak?');
      siteSpeakerOptions();
      final action = engine.console.actions.firstWhere(
        (a) => a.entityType == 'field-speaker',
      );
      final expected =
          'Persuasion ${person.skill(Skill.persuasion)} · Seduction ${person.skill(Skill.seduction)} · Disguise ${person.skill(Skill.disguise)}';
      expect(action.entityId, person.id.toString());
      expect(action.intentLabel, expected);
      final before = jsonEncode(game.gameState.toJson());
      final reader = engine.getKey();
      await mount(tester, size);
      final choice = find.ancestor(
        of: find.text(person.name),
        matching: find.byType(OutlinedButton),
      );
      await tester.ensureVisible(choice);
      expect(
        find
            .descendant(of: choice, matching: find.text(expected))
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find.descendant(of: choice, matching: find.text(person.name)),
        findsOneWidget,
      );
      expect(jsonEncode(game.gameState.toJson()), before);
      await tester.tap(choice);
      await tester.pump();
      expect(await reader, int.parse(action.key) + '0'.codeUnitAt(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'escape directions survive retries and reject stale clicks at $size',
      (tester) async {
        final before = jsonEncode(game.gameState.toJson());
        final direction = chooseSiteEscapeDirection();
        await mount(tester, size);
        expect(find.text('Cancel escape').hitTestable(), findsOneWidget);
        expect(find.text('Continue'), findsNothing);
        final rightButton = find.ancestor(
          of: find.byTooltip('Move right'),
          matching: find.byType(IconButton),
        );
        final oldClick = tester.widget<IconButton>(rightButton).onPressed!;
        expect(
          engine.console.actions.where(
            (a) => a.entityType == 'field-direction',
          ),
          hasLength(4),
        );
        expect(
          engine.console.actions
              .where((a) => a.entityType == 'field-direction')
              .every((a) => a.entityId != null && a.entityCategory == 'escape'),
          isTrue,
        );

        engine.console.sendInput('q');
        await tester.pumpAndSettle();
        oldClick();
        await tester.pump();
        expect(engine.console.awaitingInput, isTrue);
        expect(engine.console.lastKey, isNull);
        expect(find.text('Cancel escape').hitTestable(), findsOneWidget);
        final currentClick = tester.widget<IconButton>(rightButton).onPressed!;
        await tester.tap(find.byTooltip('Move right'));
        await tester.pump();
        expect(await direction, engine.Key.rightArrow);
        expect(jsonEncode(game.gameState.toJson()), before);

        // The old direction must not become an answer to a later door reader.
        final door = sitemodePrompt('A closed door.', 'Open it?');
        await tester.pumpAndSettle();
        currentClick();
        await tester.pump();
        expect(engine.console.awaitingInput, isTrue);
        expect(engine.console.lastKey, isNull);
        expect(find.text('No').hitTestable(), findsOneWidget);
        await tester.tap(find.text('No'));
        await tester.pump();
        expect(await door, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'field encounters and read-only portrait dossiers are visible at $size',
      (tester) async {
        final person = game.squad.first;
        final enemy = Creature.fromId(CreatureTypeIds.cop)
          ..name = 'QA Lobby Officer';
        game.encounter.add(enemy);
        printBasicEncounter();
        engine.mvaddstr(12, 55, 'MAP-ONLY-ASCII');
        siteMovementOptions(canMove: true);
        engine.console.screen = 'tactical';
        final reader = engine.getKey();
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 7193);
        final random = lcsRandom(100000);
        reseedRNG(seed: 7193);
        await mount(tester, size);
        expect(
          find.textContaining(enemy.name, findRichText: true),
          findsWidgets,
        );
        expect(
          find.textContaining('MAP-ONLY-ASCII', findRichText: true),
          findsNothing,
        );
        await tester.tap(find.byKey(ValueKey('field-inspect:${person.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('crew-inspector')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('crew-inspector-name')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(engine.console.awaitingInput, isTrue);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(lcsRandom(100000), random);
        await tester.tap(find.byKey(const ValueKey('crew-inspector-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
        engine.console.sendInput('Enter');
        await reader;
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'field dossier excludes background choices from Tab and activation',
    (tester) async {
      final person = game.squad.first;
      siteMovementOptions(canMove: true);
      engine.console.screen = 'tactical';
      final reader = engine.getKey();
      await mount(tester, const Size(1280, 720));
      final rightFinder = find.ancestor(
        of: find.byTooltip('Move right'),
        matching: find.byType(IconButton),
      );
      final oldMove = tester.widget<IconButton>(rightFinder).onPressed!;
      await tester.tap(find.byKey(ValueKey('field-inspect:${person.id}')));
      await tester.pumpAndSettle();
      oldMove();
      await tester.pump();
      expect(engine.console.awaitingInput, isTrue);
      final closeIcon = find.descendant(
        of: find.byKey(const ValueKey('crew-inspector-close')),
        matching: find.byIcon(Icons.close),
      );
      Focus.of(tester.element(closeIcon)).requestFocus();
      await tester.pump();
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        var inBackgroundField = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (const [
            ValueKey('journal-operation-controls'),
            ValueKey('journal-operation-report'),
          ].contains(element.widget.key)) {
            inBackgroundField = true;
          }
          return true;
        });
        expect(
          inBackgroundField,
          isFalse,
          reason:
              'Tab must not expose an operation control behind the inspector.',
        );
      }
      // Activating a focused control after traversal must not answer the source
      // reader, even if focus has left the inspector's own close/full buttons.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(engine.console.awaitingInput, isTrue);
      engine.console.sendInput('Enter');
      await reader;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('escape cancel consumes only its own direction reader', (
    tester,
  ) async {
    final before = jsonEncode(game.gameState.toJson());
    final escape = chooseSiteEscapeDirection();
    await mount(tester, const Size(1024, 720));
    await tester.tap(find.text('Cancel escape'));
    await tester.pump();
    expect(await escape, isNull);
    expect(engine.console.actions, isEmpty);
    expect(engine.console.awaitingInput, isFalse);
    expect(jsonEncode(game.gameState.toJson()), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'combat conversation publishes true availability and retries its own choices',
    (tester) async {
      final liberal = game.squad.first;
      final target = Creature.fromId(CreatureTypeIds.cop)
        ..align = Alignment.conservative
        ..isWillingToTalk = false;
      for (final person in game.squad) {
        person.prisoner = null;
      }
      game.encounter.add(target);
      game.siteAlarm = true;
      final before = jsonEncode(game.gameState.toJson());
      final talk = talkInCombat(liberal, target);
      await mount(tester, const Size(1024, 720));
      ConsoleAction action(String key) =>
          engine.console.actions.singleWhere((a) => a.key == key);
      expect(action('b').enabled, isFalse);
      expect(action('c').enabled, isFalse);
      expect(action('d').enabled, isTrue);
      expect(action('d').entityId, '${liberal.id}:${target.id}:d');
      // Direct invalid input still reaches the unchanged original acceptance
      // checks. Its rejected attempt must leave the authored choices usable.
      engine.console.sendInput('b');
      await tester.pumpAndSettle();
      expect(action('b').enabled, isFalse);
      expect(action('e').enabled, isTrue);
      await tester.ensureVisible(find.text('Do nothing'));
      expect(find.text('Do nothing').hitTestable(), findsOneWidget);
      engine.console.sendInput('Escape');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Surrender to authorities'));
      expect(
        find.text('Surrender to authorities').hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Do nothing'));
      await tester.tap(find.text('Do nothing'));
      await tester.pump();
      expect(await talk, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(engine.console.actions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ordinary conversation survives unrelated input without advancing play',
    (tester) async {
      final liberal = game.squad.first;
      final target = Creature.fromId(CreatureTypeIds.cop);
      final before = jsonEncode(game.gameState.toJson());
      final talk = talkOutsideCombat(liberal, target);
      await mount(tester, const Size(1024, 720));
      engine.console.sendInput('q');
      await tester.pumpAndSettle();
      expect(
        engine.console.actions.where((a) => a.entityType == 'conversation'),
        hasLength(3),
      );
      await tester.ensureVisible(
        find.text("On second thought, don't say anything."),
      );
      expect(
        find.text("On second thought, don't say anything.").hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text("On second thought, don't say anything."));
      await tester.pump();
      expect(await talk, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(engine.console.actions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
