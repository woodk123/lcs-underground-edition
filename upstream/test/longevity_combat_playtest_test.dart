import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/siege.dart' as siege;
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/advance.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

const reportPath = '../reports/longevity-combat-20261015';
late SaveFile baseline;
void restore([int seed = 20261015]) {
  engine.console = Console();
  game.gameState = game.GameState.fromJson(baseline.saveData);
  applyBugFixes(baseline.version);
  reseedRNG(seed: seed);
  game.mode = GameMode.base;
  game.activeSite = game.squad.first.site;
}

Future<List<String>> run(
  String label,
  Future<void> Function() action, [
  String Function(String, List<ConsoleAction>, int)? choose,
]) async {
  final frames = await playChoices(
    action,
    choose ??
        (_, a, _) => a.any((x) => x.key == 'c' && x.enabled) ? 'c' : 'Enter',
    promptLimit: 6000,
    timeout: const Duration(seconds: 55),
  );
  await File(
    '$reportPath/$label-native.txt',
  ).writeAsString(frames.join('\n\n---\n\n'));
  return frames;
}

Site isolatedSiege(SiegeType type) {
  final loc = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
  loc.siege.activeSiegeType = type;
  loc.siege.underAttack = type != SiegeType.police;
  loc.controller = SiteController.lcs;
  loc.compound
    ..fortified = true
    ..rations = 100;
  game.activeSite = loc;
  game.activeSafehouse = loc;
  for (var i = 0; i < game.pool.length; i++) {
    final p = game.pool[i];
    if (i < 2) {
      p.location = loc;
      p.base = loc;
    } else {
      p.squad = null;
    }
  }
  return loc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    baseline = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString()),
    );
    await Directory('$reportPath/saves').create(recursive: true);
  });
  setUp(restore);
  test(
    'an ordinary dead squad cleans up without a concurrent modification or duplicate deaths',
    () async {
      final people = game.squad.take(2).toList();
      for (final p in List.of(game.squad).skip(2)) {
        p.squad = null;
      }
      for (final p in people) {
        p.die();
      }
      final martyrs = game.stats.martyrs;
      game.chaseSequence = ChaseSequence(game.activeSite!);
      game.encounter.add(Creature.fromId(CreatureTypeIds.cop));
      ChaseOutcome? outcome;
      await run('dead-squad-cleanup', () async {
        outcome = await footChaseSequence(showStandardText: false);
      });
      expect(outcome, ChaseOutcome.death);
      expect(game.squad, isEmpty);
      expect(game.stats.martyrs, martyrs);
      roundTripLiveCampaign();
    },
  );
  test(
    'recording an existing death twice preserves death statistics and political effects',
    () {
      final p = game.pool.first;
      final before = game.stats.martyrs;
      p.die();
      expect(game.stats.martyrs, before + 1);
      final politics = jsonEncode(game.politics.toJson());
      p.die();
      expect(game.stats.martyrs, before + 1);
      expect(jsonEncode(game.politics.toJson()), politics);
      final enemy = Creature.fromId(CreatureTypeIds.cop)
        ..align = Alignment.conservative;
      final kills = game.stats.kills;
      enemy.die();
      expect(game.stats.kills, kills + 1);
      final after = jsonEncode(game.politics.toJson());
      enemy.die();
      expect(game.stats.kills, kills + 1);
      expect(jsonEncode(game.politics.toJson()), after);
    },
  );
  test(
    'cleared unoccupied bomber siege does not continue bombarding',
    () async {
      final loc = isolatedSiege(SiegeType.police);
      for (final p in game.pool) {
        p.location = game.sites.firstWhere(
          (s) => s.type == SiteType.homelessEncampment,
        );
      }
      loc.siege.escalationState = SiegeEscalation.bombers;
      loc.compound
        ..aaGun = true
        ..solarPanels = true;
      reseedRNG(seed: 2);
      final frames = await run('empty-bomber-raid', siege.siegeTurn);
      expect(loc.siege.underSiege, isFalse);
      expect(frames.join('\n'), isNot(contains('Planes streak overhead')));
      expect(loc.compound.aaGun, isTrue);
      expect(loc.compound.solarPanels, isTrue);
    },
  );
  for (final type in [
    SiegeType.cia,
    SiegeType.angryRuralMob,
    SiegeType.corporateMercs,
    SiegeType.ccs,
  ]) {
    test(
      'rare ${type.name} surrender kills present crew once and preserves outsiders',
      () async {
        final loc = isolatedSiege(type);
        final present = game.pool.take(2).toList();
        final outsider = game.pool.last;
        final corpse = game.pool[2];
        corpse.location = loc;
        corpse.die();
        final martyrs = game.stats.martyrs;
        await run('surrender-${type.name}', () => giveUp(loc));
        expect(loc.siege.underSiege, isFalse);
        expect(outsider.alive, isTrue);
        for (final p in present) {
          expect(p.alive, isFalse);
          expect(p.squad, isNull);
        }
        expect(game.stats.martyrs, martyrs + 2);
        if (type == SiegeType.ccs) expect(loc.controller, SiteController.ccs);
        roundTripLiveCampaign();
      },
    );
  }
  for (final funds in [0, 100, 5000]) {
    test(
      'medical debt siege surrender with $funds funds is nonlethal and reconciles',
      () async {
        final loc = isolatedSiege(SiegeType.medicalDebtCollectors);
        game.ledger.forceSetFunds(funds);
        final people = game.pool.take(2).toList();
        for (final p in people) {
          p.medicalBills = 1000;
        }
        final before = game.ledger.totalExpense;
        await run('medical-$funds', () => giveUp(loc));
        expect(people.every((p) => p.alive && p.medicalBills == 0), isTrue);
        expect(game.ledger.funds, funds - (funds < 2000 ? funds : 2000));
        expect(game.ledger.totalExpense - before, funds < 2000 ? funds : 2000);
        expect(loc.siege.timeuntilmedical, -60);
        expect(loc.siege.underSiege, isFalse);
        roundTripLiveCampaign();
      },
    );
  }
  test(
    'ordinary combat seed matrix resolves injury, ammo use, bleeding and deaths',
    () async {
      final results = <Map<String, dynamic>>[];
      for (var seed = 0; seed < 24; seed++) {
        restore(seed);
        final camp = game.activeSite!;
        for (final p in List.of(game.pool)) {
          p.squad = null;
        }
        final team = Squad()..name = 'Ordinary combat';
        game.squads.add(team);
        game.activeSquad = team;
        final actor =
            Creature.fromId(
                CreatureTypeIds.gangMember,
                align: Alignment.liberal,
              )
              ..name = 'Ordinary Shooter'
              ..location = camp
              ..base = camp;
        game.pool.add(actor);
        actor.squad = team;
        actor.giveWeaponAndAmmo('WEAPON_9MM_HANDGUN', 2);
        actor.giveArmor(Clothing('CLOTHING_CLOTHES'));
        final enemy = Creature.fromId(CreatureTypeIds.cop)
          ..align = Alignment.conservative;
        enemy.cantRunAway = true;
        game.encounter.add(enemy);
        game.mode = GameMode.footChase;
        final originalAttributes = Map.of(actor.rawAttributes);
        final originalSkill = Map.of(actor.rawSkill);
        final initialBlood = actor.blood;
        final originalAmmo =
            actor.weapon.ammo + (actor.spareAmmo?.stackSize ?? 0);
        var rounds = 0;
        await run('ordinary-duel-$seed', () async {
          while (actor.alive &&
              game.encounter.any((p) => p.alive) &&
              rounds < 30) {
            await combatRound(game.encounter);
            await creatureadvance();
            rounds++;
          }
        });
        expect(actor.rawAttributes, originalAttributes);
        expect(actor.blood, lessThanOrEqualTo(actor.maxBlood));
        expect(actor.weapon.ammo, greaterThanOrEqualTo(0));
        expect(
          actor.weapon.ammo + (actor.spareAmmo?.stackSize ?? 0),
          lessThanOrEqualTo(originalAmmo),
        );
        final capped = actor.alive && enemy.alive;
        final ammoReduction =
            originalAmmo -
            actor.weapon.ammo -
            (actor.spareAmmo?.stackSize ?? 0);
        String? retreat;
        if (capped) {
          game.chaseSequence = ChaseSequence(camp)..canpullover = true;
          await run(
            'ordinary-retreat-$seed',
            () async {
              retreat = (await footChaseSequence(showStandardText: false)).name;
            },
            (_, a, _) => a.any((x) => x.key == 'd' && x.enabled)
                ? 'd'
                : a.any((x) => x.key == 'c' && x.enabled)
                ? 'c'
                : 'Enter',
          );
        }
        final record = {
          'seed': seed,
          'combatRoundCapReached': capped,
          'retreatOutcome': retreat,
          'attributes': originalAttributes.map((k, v) => MapEntry(k.name, v)),
          'skills': originalSkill.map((k, v) => MapEntry(k.name, v)),
          'rounds': rounds,
          'alive': actor.alive,
          'bloodBefore': initialBlood,
          'bloodAfter': actor.blood,
          'enemyAlive': enemy.alive,
          'carriedAmmoReduction': ammoReduction,
          'martyrs': game.stats.martyrs,
        };
        results.add(record);
        roundTripLiveCampaign();
      }
      expect(results.any((r) => r['alive'] == false), isTrue);
      expect(results.any((r) => r['enemyAlive'] == false), isTrue);
      expect(
        results.any((r) => (r['carriedAmmoReduction'] as int) > 0),
        isTrue,
      );
      await File(
        '$reportPath/ordinary-combat-matrix.json',
      ).writeAsString(jsonEncode(results));
    },
  );
  test(
    'ordinary knife combat seed matrix resolves injuries, bleeding and retreats',
    () async {
      final results = <Map<String, dynamic>>[];
      for (var seed = 0; seed < 24; seed++) {
        restore(seed);
        final camp = game.activeSite!;
        for (final p in List.of(game.pool)) {
          p.squad = null;
        }
        final team = Squad()..name = 'Ordinary combat';
        game.squads.add(team);
        game.activeSquad = team;
        final actor =
            Creature.fromId(
                CreatureTypeIds.gangMember,
                align: Alignment.liberal,
              )
              ..name = 'Ordinary Shooter'
              ..location = camp
              ..base = camp;
        game.pool.add(actor);
        actor.squad = team;
        actor.giveWeaponAndAmmo('WEAPON_COMBATKNIFE', 2);
        actor.giveArmor(Clothing('CLOTHING_CLOTHES'));
        final enemy = Creature.fromId(CreatureTypeIds.cop)
          ..align = Alignment.conservative;
        enemy.cantRunAway = true;
        game.encounter.add(enemy);
        game.mode = GameMode.footChase;
        final originalAttributes = Map.of(actor.rawAttributes);
        final originalSkill = Map.of(actor.rawSkill);
        final initialBlood = actor.blood;
        final originalAmmo =
            actor.weapon.ammo + (actor.spareAmmo?.stackSize ?? 0);
        var rounds = 0;
        await run('ordinary-knife-duel-$seed', () async {
          while (actor.alive &&
              game.encounter.any((p) => p.alive) &&
              rounds < 30) {
            await combatRound(game.encounter);
            await creatureadvance();
            rounds++;
          }
        });
        expect(actor.rawAttributes, originalAttributes);
        expect(actor.blood, lessThanOrEqualTo(actor.maxBlood));
        expect(actor.weapon.ammo, greaterThanOrEqualTo(0));
        expect(
          actor.weapon.ammo + (actor.spareAmmo?.stackSize ?? 0),
          lessThanOrEqualTo(originalAmmo),
        );
        final capped = actor.alive && enemy.alive;
        final ammoReduction =
            originalAmmo -
            actor.weapon.ammo -
            (actor.spareAmmo?.stackSize ?? 0);
        String? retreat;
        if (capped) {
          game.chaseSequence = ChaseSequence(camp)..canpullover = true;
          await run(
            'ordinary-knife-retreat-$seed',
            () async {
              retreat = (await footChaseSequence(showStandardText: false)).name;
            },
            (_, a, _) => a.any((x) => x.key == 'd' && x.enabled)
                ? 'd'
                : a.any((x) => x.key == 'c' && x.enabled)
                ? 'c'
                : 'Enter',
          );
        }
        final record = {
          'seed': seed,
          'combatRoundCapReached': capped,
          'retreatOutcome': retreat,
          'attributes': originalAttributes.map((k, v) => MapEntry(k.name, v)),
          'skills': originalSkill.map((k, v) => MapEntry(k.name, v)),
          'rounds': rounds,
          'alive': actor.alive,
          'bloodBefore': initialBlood,
          'bloodAfter': actor.blood,
          'enemyAlive': enemy.alive,
          'carriedAmmoReduction': ammoReduction,
          'martyrs': game.stats.martyrs,
        };
        results.add(record);
        roundTripLiveCampaign();
      }
      expect(results.any((r) => r['alive'] == false), isTrue);
      expect(results.any((r) => r['enemyAlive'] == false), isTrue);

      await File(
        '$reportPath/ordinary-knife-matrix.json',
      ).writeAsString(jsonEncode(results));
    },
  );
  test(
    'rare bomber and anti-aircraft outcomes preserve ordinary crew statistics',
    () async {
      final results = <Map<String, dynamic>>[];
      for (var seed = 0; seed < 64; seed++) {
        restore(seed);
        final loc = isolatedSiege(SiegeType.police);
        loc.siege.escalationState = SiegeEscalation.bombers;
        loc.compound
          ..aaGun = true
          ..generator = true
          ..solarPanels = true
          ..bollards = true;
        final attr = game.pool.map((p) => Map.of(p.rawAttributes)).toList();
        reseedRNG(seed: seed);
        final frames = await run('bombers-$seed', siege.siegeTurn);
        final t = frames.join('\n');
        for (var i = 0; i < game.pool.length; i++) {
          expect(game.pool[i].rawAttributes, attr[i]);
        }
        results.add({
          'seed': seed,
          'planes': t.contains('Planes streak overhead'),
          'heldOff':
              t.contains('hold them off') ||
              t.contains('One of the bombers') ||
              t.contains('One of the bombers'.toLowerCase()) ||
              t.contains('shoot any down') ||
              t.contains('Hit! One'),
          'pilotThrough': t.contains('A skilled pilot'),
          'aaDestroyed': !loc.compound.aaGun,
          'solarDestroyed': !loc.compound.solarPanels,
          'deaths': game.pool.where((p) => !p.alive).length,
          'text': t,
        });
        roundTripLiveCampaign();
      }
      expect(results.any((r) => r['planes'] == true), isTrue);
      expect(results.any((r) => r['pilotThrough'] == true), isTrue);
      expect(results.any((r) => r['aaDestroyed'] == true), isTrue);
      await File(
        '$reportPath/bomber-outcomes.json',
      ).writeAsString(jsonEncode(results));
    },
  );
  test(
    'prepared ordinary combat and rare siege saves export without stat inflation',
    () async {
      var serial = 0;
      Future<void> save(String name) async {
        game.gameState.uniqueGameId = 20261015000 + serial++;
        await File('$reportPath/saves/$name.json').writeAsString(
          jsonEncode(
            SaveFile(
              gameId: game.gameState.uniqueGameId.toString(),
              version: gameVersion,
              saveData: game.gameState.toJson(),
              lastPlayed: DateTime(2026, 10, 15),
            ).toJson(),
          ),
        );
        roundTripLiveCampaign();
      }

      restore();
      final camp = game.activeSite!;
      camp.siege.activeSiegeType = SiegeType.police;
      game.laws[Law.policeReform] = DeepAlignment.moderate;
      await save('ordinary-police-sweep');
      for (final type in [
        SiegeType.cia,
        SiegeType.angryRuralMob,
        SiegeType.corporateMercs,
        SiegeType.ccs,
        SiegeType.medicalDebtCollectors,
      ]) {
        restore();
        isolatedSiege(type);
        if (type == SiegeType.medicalDebtCollectors) {
          game.ledger.forceSetFunds(100);
          for (final p in game.pool.take(2)) {
            p.medicalBills = 1000;
          }
        }
        await save('rare-${type.name}');
      }
      for (final level in [
        SiegeEscalation.nationalGuard,
        SiegeEscalation.tanks,
        SiegeEscalation.bombers,
      ]) {
        restore();
        final loc = isolatedSiege(SiegeType.police);
        loc.siege.escalationState = level;
        loc.compound
          ..aaGun = true
          ..bollards = true
          ..generator = true
          ..solarPanels = true;
        await save('police-${level.name}');
      }
    },
  );
}
