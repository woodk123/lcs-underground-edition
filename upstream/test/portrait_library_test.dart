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

  test('1402 stable catalog IDs preserve original atlas cells', () {
    expect(portraitCatalog.length, 1402);
    expect(portraitCatalog.map((entry) => entry.id).toSet().length, 1402);
    expect(
      portraitCatalog.map((entry) => entry.id),
      List.generate(1402, (id) => id),
    );
    expect(portraitCatalog[249].asset, endsWith('batch_15.webp'));
    expect(portraitCatalog[249].cell, 9);
    expect(
      portraitCatalog.where((entry) => entry.gender == Gender.female).length,
      693,
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
    expect(ensurePortraitId(person), inInclusiveRange(0, 1401));
  });

  test(
    'founder rerolls stay human, age-compatible and presentation-compatible',
    () {
      for (final age in [18, 21, 22, 35]) {
        for (final gender in [Gender.male, Gender.female, Gender.nonbinary]) {
          int? previous;
          for (var count = 0; count < 12; count++) {
            final selected = chooseFounderPortrait(
              gender: gender,
              age: age,
              seed: 18001,
              after: previous,
            );
            final entry = portraitCatalog[selected];
            expect(selected, isNot(previous));
            if (gender != Gender.nonbinary) expect(entry.gender, gender);
            expect(
              (entry.visualAge - age).abs(),
              lessThanOrEqualTo(
                age < 20
                    ? 2
                    : age < 30
                    ? 8
                    : 12,
              ),
            );
            expect(entry.background, isNot(PortraitBackground.mutant));
            expect(entry.visualAge, greaterThan(0));
            previous = selected;
          }
        }
      }
    },
  );

  test('casting exhausts age-compatible faces before repeating', () {
    game.gameState.uniqueCreatures = UniqueCreatures();
    game.pool.clear();
    game.encounter.clear();
    game.gameState.datingSessions.clear();
    game.gameState.recruitmentSessions.clear();
    final ids = <int>[];
    final suitable = portraitCatalog
        .where(
          (entry) =>
              entry.ordinaryHuman &&
              entry.gender == Gender.female &&
              (entry.visualAge - adult(1).age).abs() <= 12,
        )
        .toList();
    for (var index = 0; index < suitable.length; index++) {
      final person = adult(1000 + index);
      game.pool.add(person);
      ids.add(ensurePortraitId(person));
    }
    expect(ids.toSet().length, suitable.length);
    expect(ids.toSet(), suitable.map((entry) => entry.id).toSet());
    final next = adult(20000);
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

  test(
    'expanded ordinary faces enter founder cycling and persist in saves',
    () {
      final seen = <int>{};
      int? selected;
      for (var index = 0; index < portraitCatalog.length; index++) {
        selected = chooseFounderPortrait(
          gender: Gender.female,
          age: 22,
          seed: 44,
          after: selected,
        );
        if (!seen.add(selected)) break;
      }
      expect(seen.any((id) => id >= 378), isTrue);
      final person = adult(99000)
        ..birthDate = DateTime(game.date.year - 22)
        ..portraitId = 378
        ..portraitAssignedAge = 22;
      final restored = Creature.fromJson(jsonDecode(jsonEncode(person)));
      expect(ensurePortraitId(restored), 378);
      restored.birthDate = DateTime(restored.birthDate.year - 1);
      expect(ensurePortraitId(restored), 378);
      expect(restored.portraitAssignedAge, 22);
    },
  );

  test(
    'expanding nearest-age specialist artwork preserves legacy saved faces',
    () {
      final person = adult(99001)
        ..typeId = CreatureTypeIds.mutant
        ..birthDate = DateTime(game.date.year - 100)
        ..portraitId = 294
        ..portraitAssignedAge = 100;
      expect(portraitCatalog[294].visualAge, 68);
      expect(ensurePortraitId(person), 294);
      final restored = Creature.fromJson(jsonDecode(jsonEncode(person)));
      expect(ensurePortraitId(restored), 294);
      person.portraitId = null;
      final newer = ensurePortraitId(person);
      expect(newer, greaterThanOrEqualTo(378));
      expect(portraitCatalog[newer].visualAge, 73);
    },
  );

  test('four-digit teen and nonhuman identities survive JSON round trips', () {
    final teen = adult(99002)
      ..birthDate = DateTime(game.date.year - 14)
      ..portraitId = 1258
      ..portraitAssignedAge = 14;
    final dog = adult(99003)
      ..typeId = CreatureTypeIds.guardDog
      ..body = dogBody()
      ..portraitId = 1401
      ..portraitAssignedAge = 4;
    for (final person in [teen, dog]) {
      final restored = Creature.fromJson(jsonDecode(jsonEncode(person)));
      expect(ensurePortraitId(restored), person.portraitId);
      expect(restored.portraitAssignedAge, person.portraitAssignedAge);
    }
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
      entries.every(
        (entry) => (entry.visualAge - (game.date.year - 1950)).abs() <= 12,
      ),
      isTrue,
    );
  });

  test(
    'adult casting stays in a plausible age cohort across seeds and genders',
    () {
      game.pool.clear();
      game.encounter.clear();
      for (final age in [20, 22, 28, 35, 45, 60, 73, 84, 95]) {
        for (final gender in [Gender.female, Gender.male, Gender.nonbinary]) {
          for (var index = 0; index < 40; index++) {
            final person = adult(60000 + age * 100 + index)
              ..gender = gender
              ..typeId = CreatureTypeIds.lawyer
              ..birthDate = DateTime(game.date.year - age);
            final face = portraitCatalog[ensurePortraitId(person)];
            expect(
              (face.visualAge - person.age).abs(),
              lessThanOrEqualTo(age < 30 ? 8 : 12),
              reason:
                  'Age $age must not be cast as visual age ${face.visualAge}.',
            );
            expect(person.portraitAssignedAge, person.age);
          }
        }
      }
    },
  );

  test(
    'exhausting young faces reuses an appropriate face before an older one',
    () {
      game.pool.clear();
      game.encounter.clear();
      final young = portraitCatalog.where(
        (entry) =>
            entry.ordinaryHuman &&
            entry.gender == Gender.female &&
            (entry.visualAge - 22).abs() <= 8,
      );
      for (final face in young) {
        game.pool.add(
          adult(70000 + face.id)
            ..birthDate = DateTime(game.date.year - 22)
            ..portraitId = face.id
            ..portraitAssignedAge = 22,
        );
      }
      final newcomer = adult(71000)..birthDate = DateTime(game.date.year - 22);
      final face = ensurePortraitId(newcomer);
      expect(young.map((entry) => entry.id), contains(face));
      expect(
        (portraitCatalog[face].visualAge - 22).abs(),
        lessThanOrEqualTo(8),
      );
    },
  );

  test('age takes priority when a specialist bank has no suitable face', () {
    final youngBiker = adult(72000)
      ..typeId = CreatureTypeIds.biker
      ..birthDate = DateTime(game.date.year - 22);
    final olderPunk = adult(72001)
      ..typeId = CreatureTypeIds.punk
      ..birthDate = DateTime(game.date.year - 95);
    expect(
      (portraitCatalog[ensurePortraitId(youngBiker)].visualAge - 22).abs(),
      lessThanOrEqualTo(8),
    );
    expect(
      (portraitCatalog[ensurePortraitId(olderPunk)].visualAge - 95).abs(),
      lessThanOrEqualTo(12),
    );
    expect(
      portraitCatalog[ensurePortraitId(olderPunk)].background,
      PortraitBackground.elderly,
    );
    // A bank with no closer mutant artwork uses its nearest compatible face
    // and retains it, rather than repeatedly rerolling the same saved record.
    final elderMutant = adult(72002)
      ..typeId = CreatureTypeIds.mutant
      ..birthDate = DateTime(game.date.year - 100);
    final mutantFace = ensurePortraitId(elderMutant);
    expect(portraitCatalog[mutantFace].background, PortraitBackground.mutant);
    expect(portraitCatalog[mutantFace].visualAge, 73);
    expect(ensurePortraitId(elderMutant), mutantFace);
  });

  test('migration repairs badly aged saved faces once and keeps appropriate identities', () {
    game.pool.clear();
    game.encounter.clear();
    final mismatch = adult(73000)
      ..birthDate = DateTime(game.date.year - 22)
      ..portraitId =
          12 // Visual age 68 on a character assigned at 22.
      ..portraitAssignedAge = 22;
    final appropriate = adult(73001)
      ..birthDate = DateTime(game.date.year - 22)
      ..portraitId =
          0 // Visual age 25.
      ..portraitAssignedAge = 22;
    game.pool.addAll([mismatch, appropriate]);
    reseedRNG(seed: 812);
    final expectedRolls = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 812);
    assignKnownPortraits();
    expect(
      (portraitCatalog[mismatch.portraitId!].visualAge - 22).abs(),
      lessThanOrEqualTo(8),
    );
    expect(appropriate.portraitId, 0);
    expect(List.generate(8, (_) => lcsRandom(100000)), expectedRolls);
    final corrected = mismatch.portraitId;
    final restored = Creature.fromJson(jsonDecode(jsonEncode(mismatch)));
    expect(ensurePortraitId(restored), corrected);
    appropriate.birthDate = DateTime(appropriate.birthDate.year - 20);
    expect(ensurePortraitId(appropriate), 0);
    expect(appropriate.portraitAssignedAge, 22);
    assignKnownPortraits();
    expect(mismatch.portraitId, corrected);
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
    expect(portraitCatalog[250].asset, endsWith('batch_16.webp'));
    expect(portraitCatalog[250].cell, 0);
    expect(portraitCatalog[377].asset, endsWith('batch_23.webp'));
    expect(portraitCatalog[377].cell, 15);
    expect(portraitCatalog[378].asset, endsWith('batch_24.webp'));
    expect(portraitCatalog[378].cell, 0);
    expect(portraitCatalog[1401].asset, endsWith('batch_87.webp'));
    expect(portraitCatalog[1401].cell, 15);
    for (final entry in portraitCatalog) {
      expect(entry.cell, inInclusiveRange(0, 15));
    }
  });

  test(
    'age-compatible specialist pools remain preferred after exhausting artwork',
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
          final age = switch (type) {
            CreatureTypeIds.punk => 22,
            CreatureTypeIds.goth => 30,
            CreatureTypeIds.emo => 24,
            CreatureTypeIds.biker => 45,
            _ => 40,
          };
          final person = adult(5000 + game.pool.length)
            ..typeId = type
            ..birthDate = DateTime(game.date.year - age);
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
        final person = adult(30000 + i)
          ..typeId = CreatureTypeIds.punk
          ..birthDate = DateTime(game.date.year - 22);
        game.pool.add(person);
        final id = ensurePortraitId(person);
        final variants = seen.putIfAbsent(id, () => <int>{});
        expect(variants.add(person.portraitVariant!), isTrue);
      }
      expect(
        seen.length,
        portraitCatalog
            .where(
              (entry) =>
                  entry.background == PortraitBackground.punk &&
                  entry.gender == Gender.female &&
                  (entry.visualAge - 22).abs() <= 8,
            )
            .length,
      );
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
    expect(ensurePortraitId(person), inInclusiveRange(0, 1401));
  });
}
