import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

typedef MenuStep = String Function(Console console);

/// Drives actual original awaits, without a widget router or synthetic state
/// mutations. Every step inspects the contract while that reader is live.
Future<void> runMenu(
  Future<void> Function() start,
  List<MenuStep> steps,
) async {
  final console = engine.console;
  var index = 0;
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    expect(index, lessThan(steps.length), reason: 'Unexpected awaited prompt');
    final input = steps[index++](console);
    expect(console.sendInput(input), isTrue);
  }

  console.revision.addListener(respond);
  try {
    await start().timeout(const Duration(seconds: 5));
  } finally {
    console.revision.removeListener(respond);
  }
  expect(index, steps.length);
  expect(console.navigation, isNull, reason: 'A consumed await must not leak');
}

MenuStep menu(String section, String key) => (console) {
  expect(console.navigation?.section, section);
  expect(console.navigation?.backKey, 'Escape');
  return key;
};

MenuStep unsafe(String key) => (console) {
  expect(console.navigation, isNull);
  return key;
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String saveContents;
  setUpAll(() async {
    await ensureGameDataLoaded();
    saveContents = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(saveContents).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });

  for (final atDistrict in [false, true]) {
    test('Operations section exit preserves queued visit at '
        '${atDistrict ? 'district' : 'city'} level', () async {
      final target = game.activeSquad!.site!;
      final queued = Activity(ActivityType.visit, idString: target.idString);
      game.activeSquad!.activity = queued;
      final startDate = game.date;
      final funds = game.ledger.funds;
      final roster = game.pool.map((p) => p.id).toList();
      reseedRNG(seed: 7412);
      final nextRolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 7412);

      String sectionExit(Console console) {
        expect(console.navigation?.section, 'operations');
        expect(
          console.navigation?.backKey,
          String.fromCharCode(engine.Key.menuExit),
        );
        expect(console.navigation?.note, contains('queued destination'));
        return console.navigation!.backKey;
      }

      await runMenu(planSiteVisit, [
        if (atDistrict)
          (console) {
            expect(console.navigation?.section, 'operations');
            return console.actions
                .firstWhere(
                  (action) => action.entityType == 'district' && action.enabled,
                )
                .key;
          },
        sectionExit,
      ]);

      expect(game.activeSquad!.activity, same(queued));
      expect(game.activeSquad!.activity.idString, target.idString);
      expect(game.date, startDate);
      expect(game.ledger.funds, funds);
      expect(game.pool.map((p) => p.id), roster);
      expect(List.generate(8, (_) => lcsRandom(100000)), nextRolls);
    });
  }

  test(
    'Operations manual Back still backs up, then Cancel clears visit',
    () async {
      final target = game.activeSquad!.site!;
      final queued = Activity(ActivityType.visit, idString: target.idString);
      game.activeSquad!.activity = queued;
      await runMenu(planSiteVisit, [
        (console) => console.actions
            .firstWhere(
              (action) => action.entityType == 'district' && action.enabled,
            )
            .key,
        (console) {
          expect(game.activeSquad!.activity, same(queued));
          return 'Escape';
        },
        (console) {
          expect(game.activeSquad!.activity, same(queued));
          expect(
            console.actions.any((a) => a.entityType == 'district'),
            isTrue,
          );
          return 'Escape';
        },
      ]);
      expect(game.activeSquad!.activity.type, ActivityType.none);
    },
  );

  test('ordinary management exits keep date, funds, roster and RNG', () async {
    final startDate = game.date;
    final funds = game.ledger.funds;
    final roster = game.pool.map((p) => p.id).toList();
    reseedRNG(seed: 811);
    final nextRolls = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 811);

    await runMenu(reviewAssetsAndFormSquads, [menu('people', 'Escape')]);
    await runMenu(() => reviewMode(ReviewMode.liberals), [
      menu('people', 'a'),
      menu('people', 'Escape'),
      menu('people', 'Escape'),
    ]);
    await runMenu(() async {
      await liberalAgenda();
    }, [menu('agenda', 'Escape')]);
    await runMenu(() => equip(<Item>[]), [menu('equipment', 'Escape')]);
    await runMenu(setVehicles, [menu('equipment', 'Escape')]);

    expect(game.date, startDate);
    expect(game.ledger.funds, funds);
    expect(game.pool.map((p) => p.id), roster);
    expect(List.generate(8, (_) => lcsRandom(100000)), nextRolls);
  });

  test('Media archive and article each declare their safe exit', () async {
    final article = NewsStory()
      ..headline = 'Test archive headline'
      ..body = 'An already recorded article.'
      ..publication = Publication.times;
    game.gameState.newsArchive
      ..clear()
      ..add(article);
    final startDate = game.date;
    final funds = game.ledger.funds;
    await runMenu(mediaOverview, [
      menu('media', 'a'),
      (console) {
        expect(console.article?.title, article.headline);
        return menu('media', 'Escape')(console);
      },
      menu('media', 'Escape'),
    ]);
    expect(article.unread, isFalse);
    expect(game.date, startDate);
    expect(game.ledger.funds, funds);
  });

  test(
    'equipment recipient prompt cannot inherit section navigation',
    () async {
      game.activeSquad!.members.removeRange(2, game.squad.length);
      final clothing = game.squad.map((p) => p.equippedClothing).toList();
      final loot = <Item>[Clothing('CLOTHING_CATSUIT')];
      await runMenu(() => equip(loot), [
        menu('equipment', 'a'),
        unsafe('Enter'),
        menu('equipment', 'Escape'),
      ]);
      expect(game.squad.map((p) => p.equippedClothing), clothing);
      expect(loot, hasLength(1));
    },
  );

  test('vehicle recipient prompt cannot inherit section navigation', () async {
    game.activeSquad!.members.removeRange(2, game.squad.length);
    game.vehiclePool
      ..clear()
      ..add(Vehicle(vehicleTypes.keys.first));
    final preferred = game.squad.map((p) => p.preferredCarId).toList();
    await runMenu(setVehicles, [
      menu('equipment', 'a'),
      unsafe('Enter'),
      menu('equipment', 'Escape'),
    ]);
    expect(game.squad.map((p) => p.preferredCarId), preferred);
  });

  test('equipment location list exits without moving an item', () async {
    final site = game.activeSquad!.site!;
    final item = Clothing('CLOTHING_CATSUIT');
    site.loot.add(item);
    final locationBefore = site.loot.toList();
    final startDate = game.date;
    await runMenu(equipmentBaseAssign, [menu('equipment', 'Escape')]);
    expect(site.loot, locationBefore);
    expect(game.date, startDate);
  });

  test('amount entry clears a prior declaration and never navigates', () async {
    engine.declareMenuNavigation('equipment');
    var amount = -1;
    await runMenu(() async {
      amount = await promptAmount(0, 12);
    }, [unsafe('Enter')]);
    expect(amount, 12);
  });

  test('squad assembly remains outside safe section navigation', () async {
    await runMenu(() => assembleSquad(game.activeSquad), [unsafe('Escape')]);
  });

  test(
    'person removal confirmation never inherits profile navigation',
    () async {
      final subordinate = game.pool.firstWhere(
        (p) => p.isActiveLiberal && p.hireId != null,
      );
      final roster = game.pool.map((p) => p.id).toList();
      await runMenu(() => reviewMode(ReviewMode.liberals), [
        (console) => console.actions
            .firstWhere(
              (action) =>
                  action.entityType == 'person' &&
                  action.entityId == subordinate.id.toString(),
            )
            .key,
        menu('people', 'r'),
        unsafe('Escape'),
        menu('people', 'Escape'),
        menu('people', 'Escape'),
      ]);
      expect(game.pool.map((p) => p.id), roster);
    },
  );

  test('tactical equipment has no management section exit', () async {
    game.mode = GameMode.site;
    await runMenu(() => equip(<Item>[]), [unsafe('Escape')]);
  });

  test('victory agenda remains forced progression', () async {
    await runMenu(() async {
      await liberalAgenda(AgendaVibe.liberalVictory);
    }, [unsafe('l')]);
  });

  test('generic paged menus are not automatically safe navigation', () async {
    await runMenu(
      () => pagedInterface(
        count: 1,
        lineBuilder: (y, key, index) =>
            engine.addOptionText(y, 0, key, 'A choice'),
        onChoice: (_) async => true,
      ),
      [unsafe('Enter')],
    );
  });

  test(
    'regular bulk policy navigation leaves real assignments unchanged',
    () async {
      final before = game.pool
          .map((person) => person.activity.toJson())
          .toList();
      final date = game.date;
      await runMenu(activateRegulars, [
        menu('assignments', 'z'),
        menu('assignments', 'Escape'),
        menu('assignments', 'Escape'),
      ]);
      expect(
        game.pool.map((person) => person.activity.toJson()).toList(),
        before,
      );
      expect(game.date, date);
    },
  );
}
