import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/creature/unique_creatures.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Creature adult(int id) => Creature()
    ..id = id
    ..gender = Gender.female
    ..birthDate = DateTime(1985);

  test('378 stable catalog IDs preserve original atlas cells', () {
    expect(portraitCatalog.length, 378);
    expect(portraitCatalog.map((entry) => entry.id).toSet().length, 378);
    expect(portraitCatalog[249].asset, endsWith('batch_15.png'));
    expect(portraitCatalog[249].cell, 9);
    expect(
      portraitCatalog.where((entry) => entry.gender == Gender.female).length,
      189,
    );
  });

  test('old saves acquire saved identities and tolerate invalid IDs', () {
    final person = game.pool.first;
    expect(
      person.portraitId,
      isNotNull,
    ); // The old campaign was migrated on load.
    final portrait = ensurePortraitId(person);
    final clone = Creature.fromJson(
      jsonDecode(jsonEncode(person)) as Map<String, dynamic>,
    );
    person.name = 'Renamed';
    person.gender = Gender.nonbinary;
    person.rawSkill[Skill.art] = 20;
    expect(ensurePortraitId(clone), portrait);
    expect(ensurePortraitId(person), portrait);
    person.portraitId = 10000;
    expect(ensurePortraitId(person), inInclusiveRange(0, 377));
  });

  test('casting exhausts unused compatible faces before repeating', () {
    game.gameState.uniqueCreatures = UniqueCreatures();
    game.pool.clear();
    game.encounter.clear();
    game.gameState.datingSessions.clear();
    game.gameState.recruitmentSessions.clear();
    final ids = <int>[];
    for (var index = 0; index < 125; index++) {
      final person = adult(1000 + index);
      game.pool.add(person);
      ids.add(ensurePortraitId(person));
    }
    expect(ids.toSet().length, 125);
    final next = adult(2000);
    expect(ids, contains(ensurePortraitId(next)));
  });

  test('campaign seed changes casting without consuming gameplay RNG', () {
    game.pool.clear();
    game.encounter.clear();
    game.gameState.datingSessions.clear();
    game.gameState.recruitmentSessions.clear();
    List<int> cast(int campaign) {
      game.gameState.uniqueGameId = campaign;
      return [
        for (var index = 0; index < 20; index++)
          ensurePortraitId(adult(index + 1000)),
      ];
    }

    reseedRNG(seed: 922);
    final people = [
      for (var index = 0; index < 20; index++) adult(index + 1000),
    ];
    reseedRNG(seed: 123);
    final expected = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 123);
    for (final person in people) {
      ensurePortraitId(person);
    }
    expect(List.generate(8, (_) => lcsRandom(100000)), expected);
    expect(cast(1), isNot(cast(2)));
  });

  test('profession and age softly weight selection', () {
    game.pool.clear();
    game.encounter.clear();
    final entries = [
      for (var index = 0; index < 600; index++)
        portraitCatalog[ensurePortraitId(
          adult(1000 + index)
            ..typeId = CreatureTypeIds.lawyer
            ..birthDate = DateTime(1950),
        )],
    ];
    expect(
      entries
          .where((entry) => entry.background == PortraitBackground.professional)
          .length,
      greaterThan(260),
    );
    expect(
      entries.where((entry) => entry.visualAge == 68).length,
      greaterThan(220),
    );
  });

  test(
    'children, teens and nonhumans receive appropriate specialist faces',
    () {
      final child = adult(1000)..birthDate = DateTime(game.date.year - 7);
      expect(
        portraitCatalog[ensurePortraitId(child)].background,
        PortraitBackground.child,
      );
      final teen = adult(1001)..birthDate = DateTime(game.date.year - 16);
      expect(
        portraitCatalog[ensurePortraitId(teen)].background,
        PortraitBackground.teenager,
      );
      final animal = adult(1002)..typeId = CreatureTypeIds.guardDog;
      expect(
        portraitCatalog[ensurePortraitId(animal)].background,
        PortraitBackground.canine,
      );
    },
  );

  test(
    'migration reserves saved faces and reconciles duplicate NPC records',
    () {
      game.pool.clear();
      game.encounter.clear();
      game.gameState.datingSessions.clear();
      game.gameState.recruitmentSessions.clear();
      game.gameState.uniqueCreatures = UniqueCreatures();
      final legacy = adult(1);
      final saved = adult(2)..portraitId = 22;
      final duplicate = adult(2);
      game.pool.addAll([saved, legacy]);
      game.encounter.add(duplicate);
      assignKnownPortraits();
      expect(saved.portraitId, 22);
      expect(duplicate.portraitId, 22);
      expect(legacy.portraitId, isNot(22));
      final first = [legacy.portraitId, saved.portraitId, duplicate.portraitId];
      assignKnownPortraits();
      expect([
        legacy.portraitId,
        saved.portraitId,
        duplicate.portraitId,
      ], first);
    },
  );

  test('all shipped creature professions have explicit portrait mappings', () {
    expect(
      creatureTypes.keys.toSet().difference(
        portraitProfessionBackgrounds.keys.toSet(),
      ),
      isEmpty,
    );
  });

  test('specialist atlas offsets do not consume missing original cells', () {
    expect(portraitCatalog[250].asset, endsWith('batch_16.png'));
    expect(portraitCatalog[250].cell, 0);
    expect(portraitCatalog[377].asset, endsWith('batch_23.png'));
    expect(portraitCatalog[377].cell, 15);
    for (final entry in portraitCatalog) {
      expect(entry.cell, inInclusiveRange(0, 15));
    }
  });

  test(
    'specialist pools remain strict even after exhausting their artwork',
    () {
      game.pool.clear();
      game.encounter.clear();
      for (final type in [
        CreatureTypeIds.punk,
        CreatureTypeIds.goth,
        CreatureTypeIds.emo,
        CreatureTypeIds.biker,
        CreatureTypeIds.nun,
        CreatureTypeIds.priest,
        CreatureTypeIds.televangelist,
        CreatureTypeIds.mutant,
      ]) {
        for (var index = 0; index < 24; index++) {
          final person = adult(5000 + game.pool.length)..typeId = type;
          game.pool.add(person);
          expect(
            portraitCatalog[ensurePortraitId(person)].background,
            portraitBackgroundFor(person),
          );
        }
      }
    },
  );

  test('every nonhuman body receives matching artwork', () {
    for (final type in BodyType.values.where(
      (type) => type != BodyType.human,
    )) {
      final person = adult(10000 + type.index);
      if (type == BodyType.tank) {
        person.body = TankBody();
      } else {
        person.body = HumanoidBody()..type = type;
      }
      expect(
        portraitCatalog[ensurePortraitId(person)].background.name,
        type.name,
      );
    }
  });

  test('cosmetic identity and assignment age survive save and age changes', () {
    final person = adult(20000);
    ensurePortraitId(person);
    final originalId = person.portraitId;
    final originalAge = person.portraitAssignedAge;
    final originalVariant = person.portraitVariant;
    final clone = Creature.fromJson(
      jsonDecode(jsonEncode(person)) as Map<String, dynamic>,
    );
    clone.birthDate = DateTime(clone.birthDate.year - 20);
    expect(ensurePortraitId(clone), originalId);
    expect(clone.portraitAssignedAge, originalAge);
    expect(clone.portraitVariant, originalVariant);
  });

  test(
    'repeated base portraits have distinct persistent cosmetic variants',
    () {
      game.pool.clear();
      game.encounter.clear();
      final seen = <int, Set<int>>{};
      for (var i = 0; i < 60; i++) {
        final person = adult(30000 + i)..typeId = CreatureTypeIds.punk;
        game.pool.add(person);
        final id = ensurePortraitId(person);
        final variants = seen.putIfAbsent(id, () => <int>{});
        expect(variants.add(person.portraitVariant!), isTrue);
      }
      expect(seen.length, 2);
    },
  );

  test(
    'display lookup is deterministic and never assigns or changes state',
    () {
      final person = adult(41000)..birthDate = DateTime(game.date.year - 7);
      final before = jsonEncode(person);
      final selected = portraitIdForDisplay(person);
      expect(portraitCatalog[selected].background, PortraitBackground.child);
      expect(portraitIdForDisplay(person), selected);
      expect(jsonEncode(person), before);
      person.portraitId = 0;
      final invalidBefore = jsonEncode(person);
      expect(portraitIdForDisplay(person), selected);
      expect(jsonEncode(person), invalidBefore);
    },
  );

  test(
    'migration repairs legacy adult artwork on minors and nonhuman bodies',
    () {
      game.pool.clear();
      game.encounter.clear();
      final child = adult(42000)
        ..birthDate = DateTime(game.date.year - 7)
        ..portraitId = 0;
      final dog = adult(42001)
        ..body = dogBody()
        ..portraitId = 1;
      final tank = adult(42002)
        ..body = TankBody()
        ..portraitId = 2;
      game.pool.addAll([child, dog, tank]);
      assignKnownPortraits();
      expect(
        portraitCatalog[child.portraitId!].background,
        PortraitBackground.child,
      );
      expect(
        portraitCatalog[dog.portraitId!].background,
        PortraitBackground.canine,
      );
      expect(
        portraitCatalog[tank.portraitId!].background,
        PortraitBackground.tank,
      );
      final ids = [child.portraitId, dog.portraitId, tank.portraitId];
      assignKnownPortraits();
      expect([child.portraitId, dog.portraitId, tank.portraitId], ids);
    },
  );

  test('tank JSON retains its body discriminator and saved illustration', () {
    final person = adult(43000)
      ..typeId = CreatureTypeIds.tank
      ..body = TankBody();
    final portrait = ensurePortraitId(person);
    final json = jsonDecode(jsonEncode(person)) as Map<String, dynamic>;
    expect((json['body'] as Map<String, dynamic>)['type'], 'tank');
    final restored = Creature.fromJson(json);
    expect(restored.body, isA<TankBody>());
    expect(restored.body.type, BodyType.tank);
    expect(ensurePortraitId(restored), portrait);
    expect(portraitCatalog[portrait].background, PortraitBackground.tank);
    expect(restored.portraitVariant, person.portraitVariant);
  });

  test('negative legacy identity values still produce a valid portrait', () {
    game.gameState.uniqueGameId = -123;
    final person = adult(-1000);
    expect(ensurePortraitId(person), inInclusiveRange(0, 377));
  });
}
