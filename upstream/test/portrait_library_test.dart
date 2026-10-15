import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('250 stable catalog IDs map only to valid atlas cells', () {
    expect(portraitCatalog.length, 250);
    expect(portraitCatalog.map((entry) => entry.id).toSet().length, 250);
    expect(portraitCatalog.last.asset, endsWith('batch_15.png'));
    expect(portraitCatalog.last.cell, 9);
    expect(
      portraitCatalog.where((entry) => entry.gender == Gender.female).length,
      125,
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
    expect(ensurePortraitId(person), inInclusiveRange(0, 249));
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
      greaterThan(300),
    );
  });

  test('children and nonhuman creatures do not acquire adult faces', () {
    final child = adult(1000)..birthDate = DateTime(2010);
    expect(ensurePortraitId(child), -1);
    expect(child.portraitId, isNull);
    final animal = adult(1001)..typeId = CreatureTypeIds.guardDog;
    expect(ensurePortraitId(animal), -1);
    expect(animal.portraitId, isNull);
  });

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

  test('negative legacy identity values still produce a valid portrait', () {
    game.gameState.uniqueGameId = -123;
    final person = adult(-1000);
    expect(ensurePortraitId(person), inInclusiveRange(0, 249));
  });
}
