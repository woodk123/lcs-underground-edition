import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/identity_exposure.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Creature person;
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.site;
    game.activeSite = null;
    game.gameState.siteIdentities.active = true;
    person = game.pool.first;
    person.wantedForCrimes.clear();
    person.heat = 0;
    person.equippedClothing = Clothing('CLOTHING_ELEPHANTSUIT');
  });

  test(
    'intact mask defers charges and personal heat without clearing old ones',
    () {
      person.wantedForCrimes[Crime.theft] = 2;
      person.heat = 7;
      criminalize(person, Crime.theft);
      expect(person.wantedForCrimes[Crime.theft], 2);
      expect(person.heat, 7);
      expect(game.gameState.siteIdentities.concealedCrimes[person.id], [
        (Crime.theft, crimeHeat(Crime.theft)),
      ]);
    },
  );

  test(
    'uncovered people get full charges and cannot hide by changing outfits',
    () {
      person.equippedClothing = Clothing('CLOTHING_CLOTHES');
      criminalize(person, Crime.theft);
      person.equippedClothing = Clothing('CLOTHING_ELEPHANTSUIT');
      criminalize(person, Crime.theft);
      expect(person.wantedForCrimes[Crime.theft], 2);
      expect(person.heat, 2 * crimeHeat(Crime.theft));
    },
  );

  test('melee exposure attributes earlier crimes exactly once and survives remasking', () {
    criminalize(person, Crime.theft, heatMultiplier: 0.5);
    expect(exposeFaceFromHit(person, ranged: false, roll: (_) => 24), isTrue);
    expect(person.wantedForCrimes[Crime.theft], 1);
    expect(person.heat, (crimeHeat(Crime.theft) * 0.5).ceil());
    expect(person.clothing.concealsFace, isFalse);
    expect(person.clothing.damaged, isTrue);
    game.gameState.siteIdentities.identify(person);
    expect(person.wantedForCrimes[Crime.theft], 1);
    person.equippedClothing = Clothing('CLOTHING_ELEPHANTSUIT');
    criminalize(person, Crime.assault);
    expect(person.wantedForCrimes[Crime.assault], 1);
  });

  test('ranged and melee exposure thresholds apply per landed hit', () {
    expect(exposeFaceFromHit(person, ranged: true, roll: (_) => 10), isFalse);
    expect(exposeFaceFromHit(person, ranged: false, roll: (_) => 25), isFalse);
    expect(exposeFaceFromHit(person, ranged: true, roll: (_) => 9), isTrue);
    expect(
      exposeFaceFromHit(
        person,
        ranged: false,
        roll: (_) => throw StateError('already exposed'),
      ),
      isFalse,
    );
  });

  test(
    'real combat reports exposure and attributes earlier masked crimes',
    () async {
      final attacker = game.pool[1];
      attacker.align = Alignment.conservative;
      attacker.dropWeaponAndAmmo();
      attacker.rawSkill[Skill.martialArts] = 30;
      attacker.rawAttributes[Attribute.strength] = 1;
      person.rawSkill[Skill.dodge] = 0;
      person.rawAttributes[Attribute.agility] = 1;
      person.blood = 10000;
      for (final part in person.body.parts) {
        part.naturalArmor = 1000;
      }
      criminalize(person, Crime.theft);
      reseedRNG(seed: 420);
      final frames = await playChoices(
        () async {
          for (var i = 0; i < 30 && person.clothing.concealsFace; i++) {
            await attack(attacker, person, false, forceMelee: true);
          }
        },
        (_, _, _) => 'Enter',
        promptLimit: 150,
      );
      expect(frames.join('\n'), contains('face covering is torn open'));
      expect(person.clothing.faceCoveringDamaged, isTrue);
      expect(person.wantedForCrimes[Crime.theft], 1);
      expect(person.alive, isTrue);
    },
  );

  test('deferred crimes respect individual identity and include terrorism', () {
    final other = game.pool[1];
    other.wantedForCrimes.clear();
    other.equippedClothing = Clothing('CLOTHING_CLOTHES');
    for (var i = 0; i < 9; i++) {
      addPotentialCrime([person, other], Crime.murder);
    }
    commitPotentialCrimes();
    expect(person.wantedForCrimes, isEmpty);
    expect(other.wantedForCrimes[Crime.murder], 9);
    expect(other.wantedForCrimes[Crime.terrorism], 1);
    game.gameState.siteIdentities.identify(person);
    expect(person.wantedForCrimes[Crime.murder], 9);
    expect(person.wantedForCrimes[Crime.terrorism], 1);
  });

  test(
    'pursuit preserves concealment and exposure risk until the operation ends',
    () {
      game.mode = GameMode.footChase;
      criminalize(person, Crime.resistingArrest);
      expect(person.wantedForCrimes, isEmpty);
      expect(exposeFaceFromHit(person, ranged: true, roll: (_) => 0), isTrue);
      expect(person.wantedForCrimes[Crime.resistingArrest], 1);
    },
  );

  test('uncovered and base targets consume no exposure randomness', () {
    person.equippedClothing = Clothing('CLOTHING_CLOTHES');
    expect(
      exposeFaceFromHit(
        person,
        ranged: false,
        roll: (_) => throw StateError('uncovered'),
      ),
      isFalse,
    );
    person.equippedClothing = Clothing('CLOTHING_ELEPHANTSUIT');
    game.mode = GameMode.base;
    game.gameState.siteIdentities = SiteIdentities();
    expect(
      exposeFaceFromHit(
        person,
        ranged: false,
        roll: (_) => throw StateError('base'),
      ),
      isFalse,
    );
    criminalize(person, Crime.theft);
    expect(person.wantedForCrimes[Crime.theft], 1);
  });

  test(
    'operation evidence resolves even after return mode changes to base',
    () {
      addPotentialCrime([person], Crime.theft);
      game.mode = GameMode.base;
      commitPotentialCrimes();
      expect(person.wantedForCrimes, isEmpty);
      game.gameState.siteIdentities.identify(person);
      expect(person.wantedForCrimes[Crime.theft], 1);
      expect(game.gameState.potentialCrimes, isEmpty);
    },
  );

  test(
    'capture identifies masked suspects before removing their outfit',
    () async {
      criminalize(person, Crime.theft);
      await captureCreature(person);
      expect(person.wantedForCrimes[Crime.theft], 1);
      expect(game.gameState.siteIdentities.identified, contains(person.id));
    },
  );

  test(
    'safe escape discards unidentified evidence; next operation starts fresh',
    () {
      criminalize(person, Crime.theft);
      game.gameState.siteIdentities = SiteIdentities()..active = true;
      game.gameState.siteIdentities.identify(person);
      expect(person.wantedForCrimes, isEmpty);
      expect(person.heat, 0);
    },
  );

  test('illegal raids and CCS safehouses still do not report crimes', () {
    final site = game.sites.first;
    game.activeSite = site;
    site.controller = SiteController.ccs;
    criminalize(person, Crime.theft);
    expect(game.gameState.siteIdentities.concealedCrimes, isEmpty);
    site.controller = SiteController.lcs;
    site.siege.activeSiegeType = SiegeType.cia;
    site.siege.underAttack = true;
    criminalize(person, Crime.theft);
    expect(game.gameState.siteIdentities.concealedCrimes, isEmpty);
  });

  test('torn covering persists through save and clone, repair restores it', () {
    exposeFaceFromHit(person, ranged: false, roll: (_) => 0);
    final saved = person.clothing.toJson();
    final restored = Clothing.fromJson(saved);
    expect(restored.concealsFace, isFalse);
    expect(restored.clone().faceCoveringDamaged, isTrue);
    expect(restored.compareTo(Clothing('CLOTHING_ELEPHANTSUIT')), isNot(0));
    final bloody = Clothing('CLOTHING_ELEPHANTSUIT')..bloody = true;
    expect(restored.compareTo(bloody).sign, -bloody.compareTo(restored).sign);
    restored.damaged = false;
    expect(restored.concealsFace, isTrue);
    saved.remove('faceCoveringDamaged');
    expect(Clothing.fromJson(saved).faceCoveringDamaged, isFalse);
    person.clothing.quality = person.clothing.type.qualityLevels + 1;
    expect(person.clothing.concealsFace, isFalse);
    expect(game.gameState.toJson(), isNot(contains('siteIdentities')));
  });
}
