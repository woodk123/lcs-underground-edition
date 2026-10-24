import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_display/print_party.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/site_display.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
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
    game.mode = GameMode.site;
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

  for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
    testWidgets('encounter people precede the squad at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      journalReadingScale.value = size.width == 1024 ? 1.5 : 1;
      addTearDown(() => journalReadingScale.value = 1);
      game.activeSquadMember = null;
      game.encounter
        ..clear()
        ..addAll(game.squad.take(5));
      engine.console.screen = 'tactical';
      printParty();
      printBasicEncounter();
      final state = jsonEncode(game.gameState.toJson());
      final buffer = engine.console.buffer
          .map((row) => row.map((cell) => cell.glyph).join())
          .join('\n');
      final actions = List.of(engine.console.actions);
      final reader = engine.console.getkey();
      reseedRNG(seed: 431);
      final expectedRoll = lcsRandom(1000000);
      reseedRNG(seed: 431);

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      final people = find.byKey(const ValueKey('field-encounter-people'));
      final first = find.byKey(const ValueKey('field-encounter-row:12'));
      expect(people, findsOneWidget);
      expect(find.text('People on this square'), findsOneWidget);
      expect(first, findsOneWidget);
      expect(tester.getTopLeft(first).dy, lessThan(350));
      for (final label in ['Clothing: ', 'Weapon: ', 'Health: ']) {
        expect(
          find.descendant(
            of: people,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  (widget.textSpan?.toPlainText().contains(label) ?? false),
            ),
          ),
          findsNWidgets(game.encounter.length),
        );
      }
      // The source squad table is still available below the encounter.
      final squadRow = find.byKey(
        ValueKey('journal-person-row:${game.squad.first.id}'),
      );
      expect(
        tester.getTopLeft(squadRow).dy,
        greaterThan(tester.getBottomLeft(people).dy),
      );
      expect(engine.console.actions, orderedEquals(actions));
      expect(engine.console.awaitingInput, isTrue);
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(
        engine.console.buffer
            .map((row) => row.map((cell) => cell.glyph).join())
            .join('\n'),
        buffer,
      );
      expect(lcsRandom(1000000), expectedRoll);
      expect(tester.takeException(), isNull);
      engine.console.sendInput('Enter');
      await tester.pump();
      await reader;
    });

    testWidgets(
      'field conversation choices appear once and remain usable at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        engine.console.screen = 'field_prompt';
        engine.console.journalBodyStart = 9;
        engine.mvaddstr(9, 1, 'Eugene talks to the officer:');
        engine.addOptionText(12, 1, 'a', 'A - Surrender to authorities');
        engine.addOptionText(13, 1, 'b', 'B - Do nothing');
        final reader = engine.console.getkey();
        await tester.pumpWidget(const MainApp());
        await tester.pumpAndSettle();
        expect(
          find.text('Eugene talks to the officer:', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text('A - Surrender to authorities', findRichText: true),
          findsNothing,
        );
        expect(find.text('B - Do nothing', findRichText: true), findsNothing);
        expect(
          find.text('Surrender to authorities').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.text('Surrender to authorities'));
        await tester.pump();
        expect(await reader, 'a');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('field questions retain map and answer in place at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      journalReadingScale.value = 1.5;
      engine.console.screen = 'tactical';
      siteMovementOptions(canMove: true);
      final mainReader = engine.console.getkey();
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      final map = find.byKey(const ValueKey('tactical-map-grid'));
      final mapBefore = tester.getRect(map);
      final before = jsonEncode(game.gameState.toJson());
      engine.console.sendInput('Right');
      await mainReader;

      final decision = sitemodePrompt(
        'You shake the handle but it is locked.',
        'Force it open? (Yes or No)',
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(map), mapBefore);
      expect(find.text('Force it open? (Yes or No)'), findsOneWidget);
      expect(find.text('Yes').hitTestable(), findsOneWidget);
      expect(find.text('No').hitTestable(), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Move right'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      // An unrelated key must not dismiss the prompt or enable movement.
      engine.console.sendInput('x');
      await tester.pumpAndSettle();
      expect(find.text('No').hitTestable(), findsOneWidget);
      expect(tester.getRect(map), mapBefore);
      await tester.tap(find.text('No'));
      await tester.pump();
      expect(await decision, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);

      final message = encounterMessage('The door stays closed.');
      await tester.pumpAndSettle();
      expect(find.text('Yes'), findsNothing);
      expect(find.text('No'), findsNothing);
      expect(find.text('The door stays closed.'), findsOneWidget);
      expect(tester.getRect(map), mapBefore);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await message;

      engine.console.screen = 'tactical';
      siteMovementOptions(canMove: true);
      final nextReader = engine.console.getkey();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Move right'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      engine.console.sendInput('Enter');
      await nextReader;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('one-line question accepts yes and erase ends map context', () async {
    final decision = sitemodePromptOneLine('Open the bank vault? (Yes or No)');
    expect(engine.console.screen, 'field_prompt');
    expect(engine.console.actions.map((a) => a.key), ['y', 'n']);
    engine.console.sendInput('y');
    expect(await decision, isTrue);
    expect(engine.console.actions, isEmpty);
    engine.erase();
    expect(engine.console.screen, 'generic');
  });
}
