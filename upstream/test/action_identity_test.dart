import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ensureGameDataLoaded);

  setUp(() {
    engine.console = Console();
  });

  test(
    'equipment cursor instructions expose ammo arrows, not inventory C',
    () async {
      engine.addOptionText(10, 53, 'C', 'C - Third inventory item');
      // The unchanged equipment screen uses this descriptive legacy key label.
      engine.addOptionText(
        22,
        1,
        'Cursors',
        'Cursors - Increase or decrease ammo allocation',
      );
      expect(
        engine.console.actions.where((action) => action.key == 'c'),
        hasLength(1),
        reason:
            'Cursor instructions must not dispatch the third inventory item.',
      );
      expect(
        engine.console.actions.map((action) => action.key),
        containsAll(['Up', 'Down']),
      );
      for (final (key, code) in [
        ('Up', engine.Key.upArrow),
        ('Down', engine.Key.downArrow),
      ]) {
        final pending = engine.console.getkey();
        expect(engine.console.sendInput(key), isTrue);
        expect((await pending).codePoint, code);
      }
    },
  );

  test(
    'recruitment Call it a day keeps Enter instead of selecting recruit E',
    () async {
      for (var index = 0; index < 5; index++) {
        final key = String.fromCharCode('a'.codeUnitAt(0) + index);
        engine.addOptionText(12 + index, 0, key, '$key - Candidate $index');
      }
      engine.addOptionText(
        18,
        0,
        'Enter/Escape',
        'Enter/Escape - Call it a day',
      );
      final finish = engine.console.actions.last;
      expect(finish.key, 'Enter');
      expect(
        engine.console.actions.where((action) => action.key == 'e'),
        hasLength(1),
      );
      final pending = engine.console.getkey();
      expect(engine.console.sendInput(finish.key), isTrue);
      expect((await pending).codePoint, engine.Key.enter);
    },
  );

  test(
    'real equipment recipient prompt replaces stale inventory choices',
    () async {
      final save = SaveFile.fromJson(
        jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
            as Map<String, dynamic>,
      );
      game.gameState = game.GameState.fromJson(save.saveData);
      applyBugFixes(save.version);
      game.mode = GameMode.base;
      game.activeSquadMember = null;
      expect(game.squad.length, greaterThan(1));
      final firstOutfit = game.squad.first.clothing.type;
      final newOutfit = Clothing('CLOTHING_CATSUIT');
      final outfitType = newOutfit.type;
      final loot = <Item>[newOutfit];
      final console = engine.console;
      List<String>? recipientKeys;
      int step = 0;
      void respond() {
        if (!console.awaitingInput || console.lastKey != null) return;
        final frame = console.buffer
            .map((row) => row.map((cell) => cell.glyph).join())
            .join('\n');
        if (step == 0) {
          step++;
          console.sendInput(
            console.actions.singleWhere((a) => a.key == 'a').key,
          );
        } else if (step == 1 &&
            frame.contains('Choose a Liberal squad member')) {
          recipientKeys = console.actions.map((a) => a.key).toList();
          step++;
          console.sendInput(
            console.actions.singleWhere((a) => a.key == '2').key,
          );
        } else {
          console.sendInput('Enter');
        }
      }

      console.revision.addListener(respond);
      try {
        await equip(loot).timeout(const Duration(seconds: 5));
      } finally {
        console.revision.removeListener(respond);
      }
      expect(step, 2);
      expect(game.squad[1].clothing.type, outfitType);
      expect(game.squad.first.clothing.type, firstOutfit);
      expect(recipientKeys, isNotNull);
      expect(recipientKeys, contains('2'));
      expect(
        recipientKeys,
        isNot(contains('a')),
        reason: 'An inventory action must not remain in a recipient decision.',
      );
      expect(recipientKeys, isNot(contains('Up')));
      expect(recipientKeys, isNot(contains('Down')));
    },
  );
}
