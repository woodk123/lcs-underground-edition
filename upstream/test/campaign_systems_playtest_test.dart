import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/trouble.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
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
import 'package:lcs_new_age/monthly/sleeper_update.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/newencounter.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/stealth.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

const reportPath = '../reports/campaign-systems-20261015';
void veteran(Creature p) {
  p.rawAttributes.updateAll((a, v) => a == Attribute.wisdom ? 1 : 50);
  p.rawSkill.updateAll((s, v) => 50);
  p.juice = 1000;
  p.blood = p.maxBlood;
  p.giveWeaponAndAmmo('WEAPON_M250_MACHINEGUN', 20);
  p.giveArmor(Clothing('CLOTHING_HEAVYARMOR'));
}

Site warehouse() {
  final loc = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
  loc.controller = SiteController.lcs;
  loc.compound
    ..fortified = true
    ..boobyTraps = true
    ..rations = 20
    ..generator = true;
  loc.siege.activeSiegeType = SiegeType.police;
  for (final p in game.pool) {
    p.location = loc;
    p.base = loc;
  }
  game.activeSite = loc;
  game.activeSafehouse = loc;
  return loc;
}

Future<List<String>> choices(
  String label,
  Future<void> Function() operation, [
  String Function(String, List<ConsoleAction>, int)? choose,
]) async {
  final frames = await playChoices(
    operation,
    choose ?? (_, _, _) => 'Enter',
    timeout: const Duration(seconds: 55),
    promptLimit: 2000,
  );
  await File(
    '$reportPath/$label-native.txt',
  ).writeAsString(frames.join('\n\n---\n\n'));
  return frames;
}

void cars({bool assign = true}) {
  for (final type in [VehicleTypeIds.sportsCar, VehicleTypeIds.van]) {
    game.vehiclePool.add(Vehicle(type)..location = game.squad.first.site);
  }
  if (assign) {
    for (var i = 0; i < game.squad.length; i++) {
      final p = game.squad[i];
      p.carId = game.vehiclePool[i % 2].id;
      p.isDriver = i < 2;
      p.rawSkill[Skill.driving] = 50;
    }
  }
}

Site evacuationDrill() {
  final drill = warehouse();
  drill.siege.underAttack = true;
  drill.compound.rations = 100;
  for (final p in game.pool) {
    veteran(p);
  }
  cars();
  // Explicit open-floor evacuation drill. Normal generated enemy units and
  // trap placement remain active, but this fixture removes navigation walls.
  drill.changes.clear();
  for (var x = 0; x < MAPX; x++) {
    for (var y = 0; y < MAPY; y++) {
      drill.changes.add(SiteTileChange(x, y, 0, SITEBLOCK_DEBRIS));
      if (y == 0) {
        drill.changes.add(SiteTileChange(x, y, 0, SITEBLOCK_EXIT));
      }
    }
  }
  return drill;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    await Directory('$reportPath/saves').create(recursive: true);
  });
  setUp(() async {
    engine.console = Console();
    final save = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString()),
    );
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    reseedRNG(seed: 20261015);
    game.mode = GameMode.base;
    game.activeSite = game.squad.first.site;
  });
  test(
    'warehouse breakout completes and relocates every present crew member',
    () async {
      final loc = warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      final ids = game.pool.map((p) => p.id).toList();
      await choices(
        'warehouse-escape',
        () => siege.sallyForthPart2(loc),
        (_, a, _) => a.any((x) => x.key == 'd' && x.enabled) ? 'd' : 'Enter',
      );
      expect(loc.siege.underSiege, isFalse);
      for (final id in ids) {
        final p = game.pool.singleWhere((p) => p.id == id);
        expect(p.alive, isTrue);
        expect(p.hidingDaysLeft, inInclusiveRange(2, 4));
        expect(p.base!.type, SiteType.homelessEncampment);
        expect(p.squad, isNull);
      }
      expect(loc.compound.rations, 0);
      roundTripLiveCampaign();
    },
  );
  test(
    'warehouse defence completes, retains crew and escalates police response',
    () async {
      final loc = warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      await choices(
        'warehouse-defence',
        () => siege.sallyForthPart2(loc),
        (_, a, _) => a.any((x) => x.key == 'f' && x.enabled)
            ? 'f'
            : a.any((x) => x.key == 'c' && x.enabled)
            ? 'c'
            : 'Enter',
      );
      expect(loc.siege.underSiege, isFalse);
      expect(loc.siege.escalationState, SiegeEscalation.nationalGuard);
      expect(loc.heat, greaterThanOrEqualTo(1000));
      expect(game.squad, isNotEmpty);
      expect(game.squad.every((p) => p.alive), isTrue);
      roundTripLiveCampaign();
    },
  );
  test(
    'eight defenders promote to six and reserve crew provide cover fire',
    () async {
      final loc = warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      for (var i = 0; i < 3; i++) {
        final p = Creature.fromJson(
          jsonDecode(jsonEncode(game.pool.first.toJson())),
        );
        p.id = game.gameState.nextCreatureId++;
        p.name = 'Reserve $i';
        p.squadId = null;
        game.pool.add(p);
      }
      final reserveIds = game.pool.skip(6).map((p) => p.id).toList();
      final frames = await choices(
        'eight-defenders',
        () => siege.sallyForthPart2(loc),
        (_, a, _) => a.any((x) => x.key == 'f' && x.enabled)
            ? 'f'
            : a.any((x) => x.key == 'c' && x.enabled)
            ? 'c'
            : 'Enter',
      );
      expect(game.squad, hasLength(6));
      expect(game.pool, hasLength(8));
      expect(game.pool.every((p) => p.alive), isTrue);
      expect(
        reserveIds.any(
          (id) => frames
              .join('\n')
              .contains(game.pool.singleWhere((p) => p.id == id).name),
        ),
        isTrue,
      );
      roundTripLiveCampaign();
    },
  );
  test('two-car pursuit supports gunfire and a completed escape', () async {
    for (final p in game.pool) {
      veteran(p);
    }
    cars();
    game.chaseSequence = ChaseSequence(game.activeSite!);
    makeChasers(SiteType.policeStation, 20);
    var fought = false;
    ChaseOutcome? outcome;
    final frames = await choices(
      'two-car-pursuit',
      () async {
        outcome = await carChaseSequence();
      },
      (_, a, _) {
        if (a.any((x) => x.key == 'd' && x.enabled)) {
          if (!fought) {
            fought = true;
            return 'f';
          }
          return 'd';
        }
        return 'Enter';
      },
    );
    expect(fought, isTrue);
    expect(outcome!.won, isTrue);
    expect(frames.join('\n'), contains('open fire'));
    expect(game.vehiclePool, hasLength(2));
    roundTripLiveCampaign();
  });
  test(
    'driver loss promotes a passenger without crashing a second car',
    () async {
      cars();
      game.chaseSequence = ChaseSequence(game.activeSite!);
      game.chaseSequence!.friendcar = List.of(game.vehiclePool);
      final car = game.squad.first.car!;
      game.squad.first.die();
      await choices('replacement-driver', () async {
        await drivingupdate();
      });
      expect(game.squad.where((p) => p.car == car && p.isDriver), hasLength(1));
      expect(game.vehiclePool, hasLength(2));
    },
  );
  test(
    'a crash abandons the convoy while preserving parked vehicles',
    () async {
      cars();
      game.chaseSequence = ChaseSequence(game.activeSite!);
      game.chaseSequence!.friendcar = List.of(game.vehiclePool);
      final crashed = game.vehiclePool.first;
      final other = game.vehiclePool.last;
      final parked = Vehicle(VehicleTypeIds.jeep)..location = game.activeSite;
      game.vehiclePool.add(parked);
      final passenger = game.squad.firstWhere((p) => p.car == other);
      final before = passenger.blood;
      await choices('one-car-crash', () => crashfriendlycar(crashed));
      expect(game.vehiclePool, contains(parked));
      expect(game.vehiclePool, isNot(contains(crashed)));
      expect(game.vehiclePool, isNot(contains(other)));
      expect(passenger.car, isNull);
      expect(passenger.blood, before);
      roundTripLiveCampaign();
    },
  );
  test(
    'uppercase vehicle selection assigns a driver rather than being ignored',
    () async {
      cars(assign: false);
      final keys = ['A', '1', 'Enter'];
      await choices('driver-shortcut', setVehicles, (_, _, i) => keys[i]);
      expect(game.squad.first.preferredCarId, game.vehiclePool.first.id);
      expect(game.squad.first.preferredDriver, isTrue);
    },
  );
  test(
    'successful siege escape preserves driven cars but loses parked cars',
    () async {
      final loc = warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      cars();
      final escaped = List.of(game.vehiclePool);
      final parked = Vehicle(VehicleTypeIds.jeep)..location = loc;
      game.vehiclePool.add(parked);
      game.chaseSequence = ChaseSequence(loc);
      game.chaseSequence!.friendcar = escaped;
      await choices('escape-vehicle-retention', () => siege.escapeSiege(false));
      expect(game.vehiclePool, isNot(contains(parked)));
      for (final car in escaped) {
        expect(game.vehiclePool, contains(car));
        expect(car.location!.type, SiteType.homelessEncampment);
      }
      roundTripLiveCampaign();
    },
  );
  test(
    'regime encounter generation produces death squads, firemen, educators and mutants',
    () {
      game.laws.updateAll((_, _) => DeepAlignment.archConservative);
      final fireman = Creature.fromId(CreatureTypeIds.firefighter);
      expect(fireman.name, 'Fireman');
      expect(fireman.weapon.type.idName, 'WEAPON_FLAMETHROWER');
      expect(fireman.align, Alignment.conservative);
      expect(
        encounterProfile(SiteType.prison, true).weights,
        contains(CreatureTypeIds.educator),
      );
      expect(
        encounterProfile(SiteType.prison, true).weights,
        isNot(contains(CreatureTypeIds.prisonGuard)),
      );
      expect(
        encounterProfile(SiteType.policeStation, true, alarmTimer: 100).weights,
        contains(CreatureTypeIds.deathSquad),
      );
      expect(
        encounterProfile(SiteType.drugHouse, false).weights,
        contains(CreatureTypeIds.mutant),
      );
    },
  );
  test('two siege days consume supplies and then cause starvation', () async {
    final loc = warehouse();
    loc.compound.rations = game.pool.length;
    for (final p in game.pool) {
      p.juice = 1000;
    }
    reseedRNG(seed: 2);
    await choices('supplies-day-one', siege.siegeTurn);
    expect(loc.compound.rations, 0);
    expect(loc.siege.underAttack, isFalse);
    final blood = game.pool.map((p) => p.blood).toList();
    reseedRNG(seed: 2);
    await choices('supplies-day-two', siege.siegeTurn);
    for (var i = 0; i < game.pool.length; i++) {
      expect(game.pool[i].blood, lessThan(blood[i]));
    }
  });
  test('1984 prison disguise changes from guard uniform to lab coat', () {
    game.activeSite = game.sites.firstWhere((s) => s.type == SiteType.prison);
    game.locx = 35;
    game.locy = 1;
    game.locz = 0;
    currentTile.restricted = true;
    game.laws.updateAll((_, _) => DeepAlignment.archConservative);
    final p = game.pool.first;
    p.giveArmor(Clothing('CLOTHING_LABCOAT'));
    expect(disguiseQuality(p), DisguiseQuality.inconspicuous);
    p.giveArmor(Clothing('CLOTHING_PRISONGUARD'));
    expect(disguiseQuality(p), isNot(DisguiseQuality.inconspicuous));
  });
  test(
    'actual corporate-feudal protest changes the existing flag-offence reward',
    () async {
      final baseline = jsonEncode(game.gameState.toJson());
      int? found;
      for (var seed = 0; seed < 150; seed++) {
        game.gameState = game.GameState.fromJson(jsonDecode(baseline));
        game.laws[Law.corporate] = DeepAlignment.archConservative;
        game.laws[Law.taxes] = DeepAlignment.archConservative;
        game.laws[Law.labor] = DeepAlignment.archConservative;
        final p = game.pool.first;
        p.juice = 0;
        p.rawSkill[Skill.streetSmarts] = 50;
        reseedRNG(seed: seed);
        final frames = await choices(
          'corporate-protest',
          () => doActivityTrouble([p]),
        );
        if (frames.join('\n').contains('denounced capitalism')) {
          found = seed;
          expect(p.juice, 2);
          break;
        }
      }
      expect(found, isNotNull);
      game.gameState = game.GameState.fromJson(jsonDecode(baseline));
      final p = game.pool.first;
      p.juice = 0;
      p.rawSkill[Skill.streetSmarts] = 50;
      game.laws[Law.corporate] = DeepAlignment.moderate;
      reseedRNG(seed: found!);
      await choices('non-feudal-protest', () => doActivityTrouble([p]));
      expect(p.juice, 1);
    },
  );
  for (final type in [
    CreatureTypeIds.firefighter,
    CreatureTypeIds.mutant,
    CreatureTypeIds.deathSquad,
  ]) {
    test('real combat resolves extreme-law opponent $type', () async {
      game.laws.updateAll((_, _) => DeepAlignment.archConservative);
      for (final p in game.pool) {
        veteran(p);
      }
      game.mode = GameMode.footChase;
      final enemy = Creature.fromId(type)..align = Alignment.conservative;
      enemy.cantRunAway = true;
      game.encounter.add(enemy);
      final ammo = game.squad.first.weapon.ammo;
      await choices('regime-combat-$type', () => combatRound(game.encounter));
      expect(game.squad.first.weapon.ammo, lessThan(ammo));
      roundTripLiveCampaign();
    });
  }
  test(
    'tactical siege traps activate and vehicle evacuation completes',
    () async {
      final loc = evacuationDrill();
      var turns = 0;
      int? initialTraps;
      var trapActivated = false;
      await choices('tactical-traps-and-cars', siege.escapeOrEngage, (_, a, _) {
        if (engine.console.screen == 'tactical') {
          final traps = levelMap.all.where((t) => t.siegeTrap).length;
          initialTraps ??= traps;
          if (traps < initialTraps!) trapActivated = true;
          if (a.any((x) => x.key == 'f' && x.enabled)) return 'f';
          if (turns++ < 45) return 's';
          return 'Up';
        }
        if (a.any((x) => x.key == 'd' && x.enabled)) return 'd';
        if (a.any((x) => x.key == 'c' && x.enabled)) return 'c';
        return 'Enter';
      });
      expect(initialTraps, greaterThan(0));
      expect(trapActivated, isTrue);
      expect(loc.siege.underSiege, isFalse);
      expect(game.pool.any((p) => p.alive), isTrue);
    },
  );
  test(
    'three real persuasion meetings earn a recruit before the join offer',
    () async {
      final actor = game.pool.first;
      veteran(actor);
      final recruit = Creature.fromId(CreatureTypeIds.hippie)
        ..align = Alignment.liberal
        ..location = actor.location;
      final session = RecruitmentSession(recruit, actor)..rawEagerness = 1;
      game.recruitmentSessions.add(session);
      for (var meeting = 0; meeting < 3; meeting++) {
        var chatted = false;
        await choices(
          'recruit-meeting-$meeting',
          () async {
            expect(await completeRecruitMeeting(session, actor), isFalse);
          },
          (_, a, _) {
            if (!chatted && a.any((x) => x.key == 'b')) {
              chatted = true;
              return 'b';
            }
            return 'Enter';
          },
        );
        expect(session.rawEagerness, meeting + 2);
      }
      final count = game.pool.length;
      var offered = false;
      await choices(
        'earned-recruit-join',
        () async {
          expect(await completeRecruitMeeting(session, actor), isTrue);
        },
        (_, a, _) {
          if (!offered && a.any((x) => x.key == 'c')) {
            offered = true;
            return 'c';
          }
          if (a.any(
            (x) => x.key == 'a' && x.label.contains('regular member'),
          )) {
            return 'a';
          }
          return 'Enter';
        },
      );
      expect(game.pool, hasLength(count + 1));
      expect(recruit.boss, same(actor));
      expect(game.recruitmentSessions, isNot(contains(session)));
      roundTripLiveCampaign();
    },
  );
  test(
    'sleeper influence and embezzlement execute over three monthly updates',
    () async {
      final p = game.pool.last;
      p.squad = null;
      p.sleeperAgent = true;
      p.typeId = CreatureTypeIds.corporateManager;
      p.location = game.sites.firstWhere((s) => s.type == SiteType.corporateHQ);
      p.workLocation = p.location;
      p.infiltration = .8;
      final power = {for (final v in View.values) v: 0};
      final before = game.ledger.funds;
      p.activity = Activity(ActivityType.sleeperLiberal);
      await choices('sleeper-influence', () => sleeperEffect(p, power));
      expect(power.values.any((v) => v > 0), isTrue);
      p.activity = Activity(ActivityType.sleeperEmbezzle);
      for (var i = 0; i < 3; i++) {
        await choices('sleeper-embezzle-$i', () => sleeperEffect(p, power));
        expect(p.infiltration, inInclusiveRange(0.0, 1.0));
      }
      expect(game.ledger.funds, greaterThan(before));
      expect(p.sleeperAgent, isTrue);
      roundTripLiveCampaign();
    },
  );
  test(
    'prepared campaign-system scenarios export valid reloadable saves',
    () async {
      final baseline = jsonEncode(game.gameState.toJson());
      var serial = 0;
      void reset() {
        game.gameState = game.GameState.fromJson(jsonDecode(baseline));
        game.mode = GameMode.base;
        game.activeSite = game.squad.first.site;
        reseedRNG(seed: 20261015);
      }

      Future<void> save(String name) async {
        game.gameState.uniqueGameId = 2026101500 + serial++;
        final data = game.gameState.toJson();
        await File('$reportPath/saves/$name.json').writeAsString(
          jsonEncode(
            SaveFile(
              version: gameVersion,
              saveData: data,
              gameId: game.gameState.uniqueGameId.toString(),
              lastPlayed: DateTime(2026, 10, 15),
            ).toJson(),
          ),
        );
        roundTripLiveCampaign();
      }

      warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      await save('warehouse-breakout');
      reset();
      warehouse();
      for (final p in game.pool) {
        veteran(p);
      }
      await save('warehouse-defence');
      reset();
      final loc = warehouse();
      loc.compound.rations = 5;
      for (final p in game.pool) {
        p.juice = 1000;
      }
      await save('siege-supplies');
      reset();
      evacuationDrill();
      await save('warehouse-vehicle-evacuation');
      reset();
      final template = jsonEncode(game.pool.first.toJson());
      while (game.pool.length < 14) {
        final p = Creature.fromJson(jsonDecode(template));
        p.id = game.gameState.nextCreatureId++;
        p.name = 'Systems Tester ${p.id}';
        p.hireId = game.pool.length < 11 ? 1 : 2;
        p.squadId = null;
        game.pool.add(p);
      }
      for (final p in game.pool) {
        p.rawAttributes[Attribute.charisma] = 30;
        p.juice = 1000;
        p.activity = Activity.none();
      }
      final teams = [
        game.squads.first,
        Squad()..name = 'Second Team',
        Squad()..name = 'Third Team',
      ];
      game.squads.addAll(teams.skip(1));
      for (var i = 0; i < 12; i++) {
        game.pool[i].squad = teams[i ~/ 4];
      }
      for (final p in game.pool.skip(12)) {
        p.squad = null;
        p.sleeperAgent = true;
        p.location = game.sites.firstWhere(
          (s) => s.type == SiteType.corporateHQ,
        );
        p.infiltration = .8;
      }
      cars(assign: false);
      for (var i = 0; i < 12; i++) {
        game.pool[i].preferredCarId = game.vehiclePool.first.id;
        game.pool[i].preferredDriver = i % 4 == 0;
      }
      for (final team in teams) {
        team.activity = Activity(
          ActivityType.visit,
          idString: game.sites
              .firstWhere((s) => s.type == SiteType.publicPark)
              .idString,
        );
      }
      final recruit = Creature.fromId(CreatureTypeIds.hippie)
        ..location = game.pool.first.location;
      game.recruitmentSessions.add(
        RecruitmentSession(recruit, game.pool.first)..rawEagerness = 4,
      );
      game.gameState.date = DateTime(2023, 1, 30);
      for (final p in game.pool.where((p) => p.sleeperAgent)) {
        p.typeId = CreatureTypeIds.corporateManager;
        p.workLocation = p.location;
        p.activity = Activity(
          p != game.pool.last
              ? ActivityType.sleeperLiberal
              : ActivityType.sleeperEmbezzle,
        );
      }
      await save('large-organisation');
      reset();
      game.gameState.date = DateTime(2024, 10, 31);
      await save('presidential-election');
      reset();
      game.gameState.date = DateTime(2023, 1, 31);
      game.laws.updateAll((_, _) => DeepAlignment.eliteLiberal);
      game.house.fillRange(0, game.house.length, DeepAlignment.eliteLiberal);
      game.senate.fillRange(0, game.senate.length, DeepAlignment.eliteLiberal);
      game.court.fillRange(0, game.court.length, DeepAlignment.eliteLiberal);
      game.exec.updateAll((_, _) => DeepAlignment.eliteLiberal);
      game.publicOpinion.updateAll((_, _) => 100);
      game.ccsState = game.CCSStrength.defeated;
      await save('victory');
      for (final target in [
        SiteType.fireStation,
        SiteType.prison,
        SiteType.drugHouse,
        SiteType.corporateHQ,
      ]) {
        reset();
        game.laws.updateAll((_, _) => DeepAlignment.archConservative);
        for (final p in game.pool) {
          veteran(p);
        }
        Site? site;
        for (final s in game.sites) {
          if (s.type == target) {
            site = s;
            break;
          }
        }
        if (site == null) {
          final city = game.cities.first;
          final district = city.districts.first;
          site = Site(target, city, district);
          district.sites.add(site);
        }
        site.hidden = false;
        site.controller = SiteController.unaligned;
        site.mapped = true;
        game.activeSquad!.activity = Activity(
          ActivityType.visit,
          idString: site.idString,
        );
        cars(assign: false);
        for (var i = 0; i < game.squad.length; i++) {
          game.squad[i].preferredCarId = game.vehiclePool.first.id;
          game.squad[i].preferredDriver = i == 0;
        }
        await save('regime-${target.name}');
      }
      reset();
      warehouse();
      game.laws[Law.policeReform] = DeepAlignment.archConservative;
      game.laws[Law.deathPenalty] = DeepAlignment.archConservative;
      // Camp sweep specifically uses Death Squads under these laws.
      final camp = game.sites.firstWhere(
        (s) => s.type == SiteType.homelessEncampment,
      );
      game.activeSafehouse = camp;
      for (final p in game.pool) {
        p.location = camp;
        p.base = camp;
        veteran(p);
      }
      camp.siege.activeSiegeType = SiegeType.police;
      await save('death-squad-siege');
    },
  );
}
