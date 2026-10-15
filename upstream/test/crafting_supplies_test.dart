import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/clothing_creation.dart';
import 'package:lcs_new_age/daily/activities/flag_creation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/flag_type.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Future<List<String>> acknowledgeCraft(Future<void> Function() craft) async {
  final console = engine.console;
  final frames = <String>[];
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    frames.add(
      console.buffer.map((row) => row.map((c) => c.glyph).join()).join('\n'),
    );
    expect(
      frames,
      hasLength(1),
      reason: 'Crafting must produce one result, not another decision.',
    );
    expect(console.textInput, isFalse);
    expect(console.actions.every((action) => action.key == 'Enter'), isTrue);
    expect(console.sendInput('Enter'), isTrue);
  }

  console.revision.addListener(respond);
  try {
    await craft().timeout(const Duration(seconds: 5));
  } finally {
    console.revision.removeListener(respond);
  }
  expect(console.awaitingInput, isFalse);
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
  });

  for (final isFlag in [false, true]) {
    final kind = isFlag ? 'flag' : 'clothing';
    for (final stackSize in [1, 3]) {
      test(
        'unaffordable $kind preserves a cloth stack of $stackSize and all rolls',
        () async {
          final person = game.pool[3];
          final site = person.site!;
          final cloth = Loot(LootTypeIds.recycledCloth, stackSize: stackSize);
          site.loot.add(cloth);
          final supplyPrice = isFlag
              ? flagTypes['FLAG_RAINBOW']!.makePrice
              : clothingTypes['CLOTHING_CLOTHES']!.makePrice;
          person.activity = Activity(
            isFlag ? ActivityType.makeFlag : ActivityType.makeClothing,
            idString: isFlag ? 'FLAG_RAINBOW' : 'CLOTHING_CLOTHES:ARMOR0',
          );
          // Explicit low-cash boundary: one dollar below the original half-price.
          game.ledger.forceSetFunds(supplyPrice ~/ 2 - 1);
          final funds = game.ledger.funds;
          final expense = game.ledger.totalExpense;
          final dailyExpense = Map.of(game.ledger.dailyExpense);
          final experience = person.skillXP(Skill.tailoring);
          final date = game.date;
          final inventory = jsonEncode(
            site.loot.map((item) => item.toJson()).toList(),
          );
          final assignment = person.activity;
          reseedRNG(seed: 631842);
          final rolls = List.generate(6, (_) => lcsRandom(100000));
          reseedRNG(seed: 631842);

          final frames = await acknowledgeCraft(
            () => isFlag
                ? doActivityMakeFlag(person)
                : doActivityMakeClothing(person),
          );

          expect(frames.single, contains("doesn't have enough money"));
          expect(
            jsonEncode(site.loot.map((item) => item.toJson()).toList()),
            inventory,
            reason:
                'A rejected payment must not consume either a whole cloth item or one stack unit.',
          );
          expect(cloth.stackSize, stackSize);
          expect(game.ledger.funds, funds);
          expect(game.ledger.totalExpense, expense);
          expect(game.ledger.dailyExpense, dailyExpense);
          expect(person.skillXP(Skill.tailoring), experience);
          expect(game.date, date);
          expect(List.generate(6, (_) => lcsRandom(100000)), rolls);
          if (isFlag) {
            expect(person.activity.type, ActivityType.none);
          } else {
            expect(person.activity, same(assignment));
          }
        },
      );
    }

    test(
      'affordable $kind pays the same half-price and consumes exactly one cloth unit',
      () async {
        final person = game.pool[3];
        final site = person.site!;
        final cloth = Loot(LootTypeIds.recycledCloth, stackSize: 3);
        site.loot.add(cloth);
        final supplyPrice = isFlag
            ? flagTypes['FLAG_RAINBOW']!.makePrice
            : clothingTypes['CLOTHING_CLOTHES']!.makePrice;
        person.activity = Activity(
          isFlag ? ActivityType.makeFlag : ActivityType.makeClothing,
          idString: isFlag ? 'FLAG_RAINBOW' : 'CLOTHING_CLOTHES:ARMOR0',
        );
        final cost = supplyPrice ~/ 2;
        game.ledger.forceSetFunds(cost);
        final expense = game.ledger.totalExpense;
        final date = game.date;
        reseedRNG(seed: 631842);

        await acknowledgeCraft(
          () => isFlag
              ? doActivityMakeFlag(person)
              : doActivityMakeClothing(person),
        );

        expect(game.ledger.funds, 0);
        expect(game.ledger.totalExpense, expense + cost);
        expect(game.ledger.dailyExpense[Expense.sewingSupplies], cost);
        expect(cloth.stackSize, 2);
        expect(site.loot, contains(same(cloth)));
        expect(
          site.loot,
          hasLength(2),
          reason: 'The original result is a crafted item or recycled cloth.',
        );
        expect(person.skillXP(Skill.tailoring), greaterThan(0));
        expect(game.date, date);
        // Exact successful outcomes captured from the original handlers before
        // the payment fix: output, training and random draws are unchanged.
        expect(person.skillXP(Skill.tailoring), isFlag ? 3 : 10);
        expect(
          site.loot.last.typeName,
          isFlag ? 'FLAG_RAINBOW' : 'CLOTHING_CLOTHES',
        );
        if (!isFlag) {
          expect((site.loot.last as Clothing).quality, 2);
        }
        expect(
          List.generate(6, (_) => lcsRandom(100000)),
          isFlag
              ? [5539, 34759, 23921, 39854, 50235, 21165]
              : [23921, 39854, 50235, 21165, 68964, 1591],
        );
      },
    );
  }
}
