import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/devtools/development_bridge.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/legislation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DevelopmentBridge bridge;
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    doorInteractionOrigin = null;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    bridge = DevelopmentBridge(console: () => engine.console);
    bridge.attachUi(
      Object(),
      blockedReason: () => null,
      inputText: (_, _) async => false,
    );
  });

  test(
    'map uses known graphical cells, preserves hidden state and current capabilities',
    () async {
      game.mode = GameMode.site;
      game.activeSite = game.sites.first;
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
      levelMap[35][11][0]
        ..known = true
        ..inLOS = true;
      levelMap[34][11][0]
        ..known = true
        ..inLOS = true
        ..wall = true;
      levelMap[36][11][0]
        ..known = true
        ..inLOS = true
        ..door = true
        ..locked = true;
      levelMap[35][12][0]
        ..known = true
        ..inLOS = false;
      final hidden = levelMap[35][10][0]
        ..wall = true
        ..loot = true
        ..siegeHeavyUnit = true
        ..inLOS = true;
      final console = engine.console..screen = 'tactical';
      for (final key in ['Left', 'Right', 'Up', 'Down']) {
        console.move(console.actions.length + 10, 0);
        console.addAction(key, 'Move $key');
        console.annotateActionEntity(key, type: 'field-direction', id: key);
      }
      final pending = console.getkey();
      final saved = jsonEncode(game.gameState.toJson());
      List<Object> runtime() => [
        for (final tile in levelMap.all)
          [tile.flag, tile.siegeflag, tile.inLOS, tile.bloodCounter],
      ];
      final runtimeBefore = jsonEncode(runtime());
      final reader = console.nextKeyEvent;
      final actions = List.of(console.actions);
      reseedRNG(seed: 731);
      final rolls = List.generate(10, (_) => lcsRandom(100000));
      reseedRNG(seed: 731);
      final first = bridge.observe();
      final map = first['map'] as Map<String, dynamic>;
      final cells = (map['cells'] as List).cast<Map<String, dynamic>>();
      expect(
        cells.singleWhere((c) => c['x'] == 34 && c['y'] == 11)['kind'],
        'wall',
      );
      expect(
        cells.singleWhere((c) => c['x'] == 36 && c['y'] == 11)['label'],
        isNot(contains('Locked')),
      );
      expect(cells.any((c) => c['x'] == 35 && c['y'] == 10), false);
      expect(map['ascii'], contains('#@+'));
      final movement = (map['movement'] as List).cast<Map<String, dynamic>>();
      expect(
        movement.singleWhere((m) => m['key'] == 'Left')['obstacle'],
        'wall',
      );
      expect(
        movement.singleWhere((m) => m['key'] == 'Up')['obstacle'],
        'unknown',
      );
      expect(
        movement.singleWhere((m) => m['key'] == 'Right')['obstacle'],
        'door',
      );
      for (final entry in movement) {
        expect(
          (first['actions'] as List).cast<Map<String, dynamic>>().any(
            (a) => a['id'] == entry['actionId'],
          ),
          true,
        );
      }
      hidden
        ..wall = false
        ..loot = false
        ..siegeHeavyUnit = false;
      expect(
        bridge.observe()['map'],
        map,
        reason: 'Hidden changes must not enter observations.',
      );
      hidden
        ..wall = true
        ..loot = true
        ..siegeHeavyUnit = true;
      console.screen = 'full_map';
      final full = bridge.observe()['map'] as Map<String, dynamic>;
      expect(full['width'], MAPX);
      expect(full['height'], MAPY);
      expect((full['cells'] as List).length, 4);
      console.screen = 'tactical';
      // Door readers temporarily point the engine at the target. Observation
      // must retain the graphical position and the child's Yes/No choices.
      doorInteractionOrigin = (x: 35, y: 11, z: 0);
      game.locx = 36;
      console.screen = 'field_prompt';
      console.replaceActions({'y': 'Yes', 'n': 'No'});
      final door = bridge.observe()['map'] as Map<String, dynamic>;
      expect(door['position'], {'x': 35, 'y': 11, 'z': 0});
      expect(door['movement'], isEmpty);
      doorInteractionOrigin = null;
      game.locx = 35;
      console.screen = 'tactical';
      console.actions
        ..clear()
        ..addAll(actions);
      expect(jsonEncode(game.gameState.toJson()), saved);
      expect(jsonEncode(runtime()), runtimeBefore);
      expect(console.actions, orderedEquals(actions));
      expect(identical(console.nextKeyEvent, reader), true);
      expect(console.lastKey, isNull);
      expect(List.generate(10, (_) => lcsRandom(100000)), rolls);
      console.sendInput('Enter');
      await pending;
      game.mode = GameMode.base;
      expect(
        bridge.observe().containsKey('map'),
        false,
        reason: 'Do not expose a stale site map in base mode.',
      );
    },
  );

  test(
    'article and legislation summaries use authored text with child-reader precedence',
    () async {
      final console = engine.console;
      console.showArticle(
        title: 'Readable headline',
        publisher: 'The Liberal Guardian',
        body: 'The complete authored article.',
        date: DateTime(2023, 3, 1),
        byline: 'A reporter',
      );
      final pending = console.getkey();
      final saved = jsonEncode(game.gameState.toJson());
      final observation = bridge.observe();
      expect(observation['report'], contains('Readable headline'));
      expect(observation['report'], contains('complete authored article'));
      expect(
        (observation['reportContext'] as Map<String, dynamic>)['kind'],
        'article',
      );
      console.legislation = LegislationContext(2023)
        ..bills.add(
          LegislationBill(
            law: Law.flagBurning,
            before: DeepAlignment.eliteLiberal,
            after: DeepAlignment.liberal,
          ),
        );
      console.screen = 'generic';
      final legislation = bridge.observe();
      expect(legislation['report'], contains('Decision pending'));
      expect(
        legislation['report'],
        isNot(contains('complete authored article')),
      );
      final bill = console.legislation!.bills.single
        ..enacted = true
        ..outcome = 'Signed into law.';
      expect(bridge.observe()['report'], contains(bill.outcome!));
      console.mvaddstr(0, 62, 'House');
      console.mvaddstr(2, 62, '218 Yea');
      console.mvaddstr(3, 62, '217 Nay');
      expect(bridge.observe()['report'], contains('House: 218 Yea · 217 Nay'));
      console.eventMessage = 'A child acknowledgement owns this input.';
      expect(bridge.observe()['report'], console.eventMessage);
      expect(
        (bridge.observe()['reportContext'] as Map<String, dynamic>)['kind'],
        'message',
      );
      expect(jsonEncode(game.gameState.toJson()), saved);
      expect(console.lastKey, isNull);
      console.sendInput('Enter');
      await pending;
    },
  );
}
