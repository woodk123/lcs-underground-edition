import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/site_display.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void oldHeadquarters(Console console) {
  console.move(0, 0);
  console.addstr('The Liberal Crime Squad — Headquarters');
  console.move(2, 0);
  console.addstr('Felix Kobayashi · Lay Low · Homeless Camp');
  console.move(4, 0);
  console.addstr('Older crew and party rows remain in this original buffer.');
  console.move(23, 0);
  console.addstr('W - Wait a day');
  console.move(23, 0);
  console.addAction('w', 'W - Wait a day');
  console.screen = 'headquarters';
}

Object bufferContents(Console console) => console.buffer
    .map(
      (row) => row
          .map(
            (cell) => (
              cell.glyph,
              cell.foreground,
              cell.background,
              cell.mouseClickKey,
            ),
          )
          .toList(),
    )
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    clearScreenOnNextMessage = false;
    game.gameState = decodeSaveContents(fixture).gameState!;
  });
  tearDown(() => clearScreenOnNextMessage = false);

  test(
    'inline combat reports omit freshly redrawn encounter and loot rows',
    () async {
      game.mode = GameMode.site;
      game.encounter.add(Creature.fromId(CreatureTypeIds.swat));
      clearMessageArea();
      engine.mvaddstr(9, 1, 'Felix hits the attacker.');
      engine.mvaddstr(10, 1, 'The armor absorbs part of the shot.');
      printEncounter();
      engine.console.writeStatus(
        () => engine.mvaddstr(24, 57, 'Loot on the ground!'),
      );
      final before = bufferContents(engine.console);
      final flow = engine.acknowledge(title: 'Operation report');
      expect(
        engine.console.eventMessage,
        'Felix hits the attacker.\nThe armor absorbs part of the shot.',
      );
      expect(bufferContents(engine.console), before);
      expect(engine.console.awaitingInput, isTrue);
      engine.console.sendInput('Enter');
      await flow;
      expect(engine.console.eventMessage, isNull);
      game.mode = GameMode.base;
    },
  );

  for (final clearScreen in [false, true]) {
    test(
      'full notice is exposed during its original await, clearScreen=$clearScreen',
      () async {
        const message =
            'Congress is acting on legislation! This full original announcement '
            'can exceed the old eighty-column row — every word must remain available.';
        final console = engine.console;
        oldHeadquarters(console);
        final expected = Console();
        oldHeadquarters(expected);
        engine.console = expected;
        if (clearScreen) {
          engine.erase();
        } else {
          makeDelimiter();
        }
        engine.mvaddstrc(8, 1, red, message);
        engine.console = console;
        clearScreenOnNextMessage = clearScreen;
        final state = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 874321);
        final rolls = List.generate(6, (_) => lcsRandom(100000));
        reseedRNG(seed: 874321);
        final revision = console.revision.value;

        final showing = showMessage(message, color: red);

        expect(console.awaitingInput, isTrue);
        expect(console.eventMessage, message);
        expect(console.eventMessage!.length, greaterThan(console.width));
        expect(bufferContents(console), bufferContents(expected));
        expect(
          console.actions.map((action) => action.key),
          expected.actions.map((action) => action.key),
        );
        expect(
          console.revision.value,
          revision + 1,
          reason: 'Metadata must not add another flush or wait.',
        );
        expect(jsonEncode(game.gameState.toJson()), state);
        expect(console.sendInput('Enter'), isTrue);
        await showing;

        expect(console.awaitingInput, isFalse);
        expect(console.eventMessage, isNull);
        expect(console.screen, 'generic');
        expect(
          console.sendInput('Enter'),
          isFalse,
          reason: 'Exactly one acknowledgement closes the notice.',
        );
        expect(bufferContents(console), bufferContents(expected));
        expect(jsonEncode(game.gameState.toJson()), state);
        expect(List.generate(6, (_) => lcsRandom(100000)), rolls);
      },
    );
  }

  for (final key in ['Enter', 'Space', 'Escape']) {
    test(
      'notice preserves the original any-key acknowledgement: $key',
      () async {
        final console = engine.console;
        final showing = showMessage('The squad has arrived.', delimeter: false);
        expect(console.eventMessage, 'The squad has arrived.');
        expect(console.awaitingInput, isTrue);
        expect(console.sendInput(key), isTrue);
        await showing;
        expect(console.eventMessage, isNull);
        expect(console.awaitingInput, isFalse);
        expect(console.lastKey, isNull);
      },
    );
  }

  test('ordinary nested metadata restores the previous notice', () async {
    final console = engine.console;
    console.eventMessage = 'Outer notice';
    console.eventTitle = 'Outer title';
    final showing = showMessage('Inner notice', title: 'Inner title');
    expect(console.eventMessage, 'Inner notice');
    expect(console.eventTitle, 'Inner title');
    expect(console.sendInput('Enter'), isTrue);
    await showing;
    expect(console.eventMessage, 'Outer notice');
    expect(console.eventTitle, 'Outer title');
    console.erase();
    expect(console.eventMessage, isNull);
    expect(console.eventTitle, isNull);
  });

  test('erase during the reader never restores a stale outer notice', () async {
    final console = engine.console;
    console.eventMessage = 'Old outer notice';
    final showing = showMessage('Current notice');
    expect(console.eventMessage, 'Current notice');
    console.erase();
    expect(console.eventMessage, isNull);
    expect(
      console.awaitingInput,
      isTrue,
      reason: 'Erase must not add, consume or replace the original reader.',
    );
    expect(console.sendInput('Enter'), isTrue);
    await showing;
    expect(console.eventMessage, isNull);
    expect(console.awaitingInput, isFalse);
  });

  test('cleanup does not overwrite newer presentation metadata', () async {
    final console = engine.console;
    final showing = showMessage('Old notice');
    console.eventMessage = 'New notice';
    expect(console.sendInput('Enter'), isTrue);
    await showing;
    expect(console.eventMessage, 'New notice');
  });
}
