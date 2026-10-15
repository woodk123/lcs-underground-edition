import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/siege.dart' as daily;
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/ammo_type.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/monthly/advance_month.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/load_cpc_images.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/advance.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    final save = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString()),
    );
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    reseedRNG(seed: 20261014);
    game.mode = GameMode.footChase;
    game.activeSite = game.squad.first.site;
  });
  Future<List<String>> enter(Future<void> Function() f) =>
      playChoices(f, (_, _, _) => 'Enter');

  test(
    'weapon attack snapshots retain ammo damage across another inspection',
    () {
      final a = Weapon('WEAPON_9MM_HANDGUN')
        ..ammo = 5
        ..loadedAmmoId = 'AMMO_9MM';
      final b = Weapon('WEAPON_9MM_HANDGUN')
        ..ammo = 5
        ..loadedAmmoId = 'AMMO_9MM';
      final template = a.type.attacks.firstWhere((a) => a.usesAmmo);
      final before = template.damage;
      final first = a.getAttack(true, false, true)!;
      // Temporarily distinct ammunition performance to expose aliasing even where
      // the current XML has only one cartridge-compatible 9mm load.
      final ammo = ammoTypes['AMMO_9MM']!;
      final damage = ammo.damage;
      try {
        ammo.damage = damage + 17;
        final second = b.getAttack(true, false, true)!;
        expect(first.damage, damage);
        expect(second.damage, damage + 17);
        expect(template.damage, before);
      } finally {
        ammo.damage = damage;
        template.damage = before;
      }
    },
  );
  test(
    'legacy loaded firearms select a ranged attack immediately after import',
    () {
      for (final p in game.squad.where((p) => p.weapon.ammo > 0)) {
        expect(p.weapon.loadedAmmoType, isNotNull, reason: p.name);
        expect(p.getAttack(true, false, true), isNotNull, reason: p.name);
        expect(p.getAttack(false, false, true)!.ranged, isTrue, reason: p.name);
      }
    },
  );
  test(
    'prepared scenarios export reproducible current-schema browser saves',
    () async {
      final dir = Directory('../reports/deep-playtest-20261014/saves');
      await dir.create(recursive: true);
      final baseline = jsonEncode(game.gameState.toJson());
      Future<void> output(String name, int id) async {
        game.gameState.uniqueGameId = id;
        await File('${dir.path}/$name.json').writeAsString(
          jsonEncode(
            SaveFile(
              version: gameVersion,
              saveData: game.gameState.toJson(),
              gameId: id.toString(),
              lastPlayed: DateTime(2026, 10, 14),
            ).toJson(),
          ),
        );
      }

      final warehouse = game.sites.firstWhere(
        (s) => s.type == SiteType.warehouse,
      );
      warehouse.controller = SiteController.lcs;
      warehouse.compound
        ..fortified = true
        ..boobyTraps = true
        ..rations = 6;
      warehouse.siege.activeSiegeType = SiegeType.police;
      for (final p in game.pool) {
        p.location = warehouse;
        p.base = warehouse;
      }
      game.activeSafehouse = warehouse;
      await output('warehouse-siege', 2026101401);
      game.gameState = game.GameState.fromJson(jsonDecode(baseline));
      game.gameState.date = DateTime(2023, 1, 31);
      final people = List.of(game.pool);
      final station = game.sites.firstWhere(
        (s) => s.type == SiteType.policeStation,
      );
      people[1]
        ..squad = null
        ..location = game.sites.firstWhere(
          (s) => s.type == SiteType.courthouse,
        );
      criminalize(people[1], Crime.theft);
      people[2]
        ..squad = null
        ..sentence = 1
        ..deathPenalty = true;
      imprison(people[2]);
      people[3]
        ..squad = null
        ..sentence = 1;
      imprison(people[3]);
      people[4]
        ..squad = null
        ..location = station;
      criminalize(people[4], Crime.illegalEntry);
      game.laws[Law.immigration] = DeepAlignment.conservative;
      game.laws[Law.deathPenalty] = DeepAlignment.conservative;
      await output('justice-rollover', 2026101402);
      game.gameState = game.GameState.fromJson(jsonDecode(baseline));
      game.laws.updateAll((_, _) => DeepAlignment.archConservative);
      await output('extreme-laws', 2026101403);
      game.gameState = game.GameState.fromJson(jsonDecode(baseline));
      final second = Squad()..name = 'Second Squad';
      game.squads.add(second);
      game.pool[2].squad = second;
      game.pool[3].squad = second;
      game.pool[4]
        ..squad = null
        ..sleeperAgent = true;
      await output('two-squads-sleeper', 2026101404);
    },
  );
  for (final execute in [false, true]) {
    test(
      'monthly illegal-entry detention resolves ${execute ? "execution" : "deportation"}',
      () async {
        await loadCpcGraphics();
        final p = game.pool.last;
        p.squad = null;
        p.location = game.sites.firstWhere(
          (s) => s.type == SiteType.policeStation,
        );
        criminalize(p, Crime.illegalEntry);
        game.gameState.date = DateTime(2023, 2, 1);
        game.laws[Law.immigration] = DeepAlignment.archConservative;
        game.laws[Law.deathPenalty] = execute
            ? DeepAlignment.archConservative
            : DeepAlignment.conservative;
        final frames = await enter(advanceMonth);
        expect(game.pool.any((person) => person.id == p.id), isFalse);
        expect(frames.join('\n'), contains(execute ? 'executed' : 'deported'));
      },
    );
  }
  test(
    'presidential election resolves and persists its political results',
    () async {
      await loadCpcGraphics();
      game.gameState.date = DateTime(2024, 11, 1);
      final before = jsonEncode(game.politics.toJson());
      final frames = await playChoices(
        advanceMonth,
        (_, _, _) => 'Enter',
        timeout: const Duration(seconds: 40),
      );
      expect(frames.join('\n'), contains('Presidential'));
      expect(jsonEncode(game.politics.toJson()), isNot(before));
      expect(game.house, hasLength(435));
      expect(game.senate, hasLength(100));
      roundTripLiveCampaign();
    },
  );
  test(
    'aggressive CCS progresses through all three monthly escalation gates',
    () async {
      await loadCpcGraphics();
      game.ccsState = game.CCSStrength.inHiding;
      game.ccsAggressive = true;
      for (final (month, state) in [
        (2, game.CCSStrength.active),
        (3, game.CCSStrength.attacks),
        (4, game.CCSStrength.sieges),
      ]) {
        game.gameState.date = DateTime(2023, month, 1);
        await enter(advanceMonth);
        expect(game.ccsState, state);
        roundTripLiveCampaign();
      }
    },
  );
  test(
    'empty firearm reload consumes a combat turn and survives save',
    () async {
      final p = game.squad.first;
      p.giveWeaponAndAmmo('WEAPON_9MM_HANDGUN', 1);
      p.weapon.ammo = 0;
      p.spareAmmo = Ammo('AMMO_9MM', stackSize: 3);
      final target = game.squad[1];
      final blood = target.blood;
      final frames = await enter(() async {
        expect(await attack(p, target, false), isFalse);
      });
      expect(frames.join('\n'), contains('reloads'));
      expect(target.blood, blood);
      expect(p.weapon.ammo, 3);
      expect(p.spareAmmo, isNull);
      expect(p.reload(true), isFalse);
      roundTripLiveCampaign();
      expect(game.pool.singleWhere((x) => x.id == p.id).weapon.ammo, 3);
    },
  );
  test('damaged armour retains exact protection through a campaign reload', () {
    final p = game.squad.first;
    p.giveArmor(Clothing('CLOTHING_POLICEARMOR'));
    final torso = p.body.parts.firstWhere(
      (part) => part.critical && !part.weakSpot,
    );
    final before = p.clothing.getArmorForLocation(torso);
    expect(before, greaterThan(17));
    p.clothing.damageArmorInLocation(torso, 17);
    expect(p.clothing.getArmorForLocation(torso), before - 17);
    roundTripLiveCampaign();
    final loaded = game.pool.singleWhere((x) => x.id == p.id);
    expect(loaded.clothing.bodyArmor, before - 17);
    expect(loaded.clothing.damaged, isTrue);
  });
  test('incompatible ammunition cannot reload or consume reserves', () {
    final p = game.squad.first;
    p.giveWeaponAndAmmo('WEAPON_9MM_HANDGUN', 1);
    p.weapon.ammo = 0;
    p.spareAmmo = Ammo('AMMO_44', stackSize: 12);
    expect(p.reload(true), isFalse);
    expect(p.weapon.ammo, 0);
    expect(p.spareAmmo!.stackSize, 12);
  });
  test('unstunned medic can stop another squad member bleeding', () async {
    final patient = game.squad.first;
    final medic = game.squad[1];
    for (final p in game.squad) {
      p.rawSkill[Skill.firstAid] = 0;
    }
    medic.rawSkill[Skill.firstAid] = 100;
    medic.stunned = 0;
    patient.body.parts.first.bleeding = 10;
    final frames = await enter(() => advancecreature(patient));
    expect(patient.body.parts.first.bleeding, 0);
    expect(frames.join('\n'), contains('was able to slow the bleeding'));
  });
  test('stunned medic cannot treat another squad member bleeding', () async {
    final patient = game.squad.first;
    for (final p in game.squad) {
      p.rawSkill[Skill.firstAid] = 0;
    }
    final medic = game.squad[1]..stunned = 5;
    medic.rawSkill[Skill.firstAid] = 100;
    patient.body.parts.first.bleeding = 10;
    final blood = patient.blood;
    await enter(() => advancecreature(patient));
    expect(patient.blood, lessThan(blood));
    expect(patient.body.parts.first.bleeding, greaterThan(0));
  });
  test('untreated bleeding kills and persists death', () async {
    final p = game.squad.first;
    for (final p in game.squad) {
      p.rawSkill[Skill.firstAid] = 0;
    }
    p.blood = 1;
    p.body.parts.first.bleeding = 100;
    await enter(() => advancecreature(p));
    expect(p.alive, isFalse);
    roundTripLiveCampaign();
    expect(game.pool.singleWhere((x) => x.id == p.id).alive, isFalse);
  });
  test('forced knife attack resolves without ammunition', () async {
    final p = game.squad.first;
    final target = game.squad[1];
    p.giveWeaponAndAmmo('WEAPON_COMBATKNIFE', 0);
    game.encounter.add(target);
    final frames = await enter(() async {
      await attack(p, target, false, forceMelee: true);
    });
    expect(frames, isNotEmpty);
    expect(p.weapon.ammo, 0);
  });
  test(
    'police siege surrender detains every announced camp arrestee',
    () async {
      final loc = game.activeSite!;
      loc.siege.activeSiegeType = SiegeType.police;
      for (final p in game.pool) {
        p.wantedForCrimes.updateAll((_, _) => 0);
      }
      final ids = game.squad.map((p) => p.id).toList();
      await enter(() => giveUp(loc));
      for (final id in ids) {
        final p = game.pool.singleWhere((p) => p.id == id);
        expect(p.site!.type, SiteType.policeStation);
        expect(p.squad, isNull);
        expect(p.equippedWeapon, isNull);
      }
      expect(loc.siege.underSiege, isFalse);
      roundTripLiveCampaign();
    },
  );
  test(
    'siege ration display matches turns before starvation and both APIs agree',
    () {
      final loc = game.activeSite!;
      expect(numberEating(loc), 5);
      loc.compound.rations = 6;
      expect(foodDaysLeft(loc), 2);
      expect(loc.foodDaysLeft, 2);
      loc.compound.rations = 1;
      expect(foodDaysLeft(loc), 1);
      expect(loc.foodDaysLeft, 1);
    },
  );
  test(
    'siege turn consumes supplies without starvation when rations remain',
    () async {
      final loc = game.activeSite!;
      loc.siege.activeSiegeType = SiegeType.police;
      loc.compound.rations = 1;
      loc.compound.fortified = true;
      final blood = game.pool.map((p) => p.blood).toList();
      await enter(daily.siegeTurn);
      expect(loc.compound.rations, 0);
      expect(game.pool.map((p) => p.blood).toList(), blood);
    },
  );
  test(
    'death row execution and abolition commutation use real prison rules',
    () async {
      final p = game.squad[1];
      imprison(p);
      p.deathPenalty = true;
      p.sentence = 1;
      game.laws[Law.deathPenalty] = DeepAlignment.eliteLiberal;
      await enter(() => prison(p));
      expect(p.alive, isTrue);
      expect(p.sentence, -1);
      expect(p.deathPenalty, isFalse);
      p.deathPenalty = true;
      p.sentence = 1;
      game.laws[Law.deathPenalty] = DeepAlignment.archConservative;
      await enter(() => prison(p));
      expect(p.alive, isFalse);
      roundTripLiveCampaign();
    },
  );
  test('monthly execution records exactly one martyr', () async {
    await loadCpcGraphics();
    final p = game.pool.last;
    p.squad = null;
    imprison(p);
    p
      ..sentence = 1
      ..deathPenalty = true;
    game.laws[Law.deathPenalty] = DeepAlignment.archConservative;
    game.gameState.date = DateTime(2023, 2, 1);
    final before = game.stats.martyrs;
    await enter(advanceMonth);
    expect(p.alive, isFalse);
    expect(game.stats.martyrs, before + 1);
  });
  test('all extreme combinations activate only with their actual gates', () {
    game.laws.updateAll((_, _) => DeepAlignment.archConservative);
    expect(game.deathSquadsActive, isTrue);
    expect(game.fahrenheit451, isTrue);
    expect(game.nineteenEightyFour, isTrue);
    expect(game.corporateFeudalism, isTrue);
    expect(game.mutantsCommon, isTrue);
    game.laws[Law.policeReform] = DeepAlignment.conservative;
    expect(game.deathSquadsActive, isFalse);
    expect(game.fahrenheit451, isFalse);
    expect(game.nineteenEightyFour, isFalse);
    expect(game.corporateFeudalism, isTrue);
    game.laws[Law.pollution] = DeepAlignment.moderate;
    expect(game.mutantsCommon, isFalse);
    expect(game.mutantsPossible, isTrue);
    roundTripLiveCampaign();
  });
}
