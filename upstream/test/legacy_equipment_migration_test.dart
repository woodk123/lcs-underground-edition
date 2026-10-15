import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);

  for (final fixture in ['felix_1_0.json', 'EQ_1_1.json']) {
    test(
      '$fixture retains every worn outfit and its protection on import',
      () async {
        final raw =
            jsonDecode(await File('test/saves/$fixture').readAsString())
                as Map<String, dynamic>;
        final data = raw['saveData'] is String
            ? jsonDecode(raw['saveData'] as String) as Map<String, dynamic>
            : raw['saveData'] as Map<String, dynamic>;
        final expected = <int, Map<String, dynamic>>{};
        for (final person
            in (data['lcs'] as Map<String, dynamic>)['pool'] as List) {
          final record = person as Map<String, dynamic>;
          if (record['equippedArmor'] is Map<String, dynamic>) {
            expected[record['id'] as int] = Map<String, dynamic>.from(
              record['equippedArmor'] as Map,
            );
          }
        }
        expect(expected, isNotEmpty);
        final save = SaveFile.fromJson(raw);
        game.gameState = game.GameState.fromJson(save.saveData);
        applyBugFixes(save.version);
        for (final person in game.pool.where(
          (p) => expected.containsKey(p.id),
        )) {
          final old = expected[person.id]!;
          final type = mapOutdatedItem(old['typeName'] as String);
          final outfit = person.equippedClothing;
          expect(
            outfit,
            isNotNull,
            reason: '${person.name} lost their outfit.',
          );
          expect(person.indecent, isFalse, reason: person.name);
          expect(outfit!.typeName, type);
          expect(outfit.stackSize, old['stackSize']);
          expect(outfit.bloody, old['bloody']);
          expect(outfit.damaged, old['damaged']);
          final reference = Clothing(type);
          expect(outfit.bodyArmor, reference.maxBodyArmor, reason: person.name);
          expect(outfit.headArmor, reference.maxHeadArmor, reason: person.name);
        }
        final serialized = jsonEncode(game.gameState.toJson());
        game.gameState = game.GameState.fromJson(
          jsonDecode(serialized) as Map<String, dynamic>,
        );
        expect(jsonEncode(game.gameState.toJson()), serialized);
      },
    );
  }

  test('mixed schemas preserve explicit current clothing and naked states', () {
    final current = Clothing('CLOTHING_CHEAPSUIT').toJson();
    final data = {
      'lcs': {
        'pool': [
          {
            'equippedClothing': current,
            'equippedArmor': {
              'typeName': 'ARMOR_CLOTHES',
              'stackSize': 1,
              'bloody': false,
              'damaged': false,
            },
          },
          {
            'equippedClothing': null,
            'equippedArmor': {
              'typeName': 'ARMOR_CLOTHES',
              'stackSize': 1,
              'bloody': false,
              'damaged': false,
            },
          },
        ],
      },
    };
    final save = SaveFile.fromJson({
      'gameId': 'migration-test',
      'version': '1.1.0',
      'saveData': data,
      'lastPlayed': null,
    });
    final people = (save.saveData['lcs'] as Map)['pool'] as List;
    expect((people[0] as Map)['equippedClothing'], current);
    expect((people[1] as Map)['equippedClothing'], isNull);
  });

  test(
    'legacy outfit migration preserves damage, quality and embedded records',
    () {
      final save = SaveFile.fromJson({
        'gameId': 'embedded-migration-test',
        'version': '1.1.0',
        'lastPlayed': null,
        'saveData': {
          'newsArchive': [
            {
              'cr': {
                'equippedArmor': {
                  'typeName': 'ARMOR_POLICEARMOR',
                  'stackSize': 1,
                  'bloody': true,
                  'damaged': true,
                  '_quality': 2,
                },
              },
            },
          ],
        },
      });
      final stories = save.saveData['newsArchive'] as List;
      final person = (stories.single as Map)['cr'] as Map;
      final outfit = Clothing.fromJson(
        person['equippedClothing'] as Map<String, dynamic>,
      );
      expect(person.containsKey('equippedArmor'), isFalse);
      expect(outfit.typeName, 'CLOTHING_POLICEARMOR');
      expect(outfit.bloody, isTrue);
      expect(outfit.damaged, isTrue);
      expect(outfit.quality, 2);
      expect(outfit.bodyArmor, greaterThan(0));
    },
  );
}
