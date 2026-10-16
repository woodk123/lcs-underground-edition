import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/daily/siege.dart' as siege;
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/haul_kidnap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

extension on Body {
  BodyPart get torso => (this as HumanoidBody).torso;
}

String _person(Creature person) => jsonEncode(person.toJson());
String _team(Squad squad) => jsonEncode(squad.toJson());
String _equipment(Creature person) => jsonEncode([
  person.equippedWeapon?.toJson(),
  person.equippedClothing?.toJson(),
  person.spareAmmo?.toJson(),
]);

/// Existing bundled crew, separated into local defenders, one hospital patient
/// based at the threatened rented warehouse, and a squad physically elsewhere.
/// No combat attributes, skills or weapon balance are changed by this setup.
class _SiegeCampaign {
  _SiegeCampaign() {
    final crew = game.pool.toList();
    local = crew.take(2).toList();
    patient = crew[2];
    remote = crew.skip(3).toList();
    home = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
    camp = game.sites.firstWhere(
      (s) => s.type == SiteType.homelessEncampment && s.city == home.city,
    );
    hospital = game.sites.firstWhere(
      (s) => s.type == SiteType.universityHospital && s.city == home.city,
    );
    for (final person in crew) {
      person.squad = null;
      person.wantedForCrimes.updateAll((_, _) => 0);
      person.activity = Activity.none();
    }
    game.squads.clear();
    localSquad = Squad()..name = 'Local siege crew';
    remoteSquad = Squad()..name = 'Offsite crew';
    game.squads.addAll([localSquad, remoteSquad]);
    for (final person in local) {
      person.location = home;
      person.base = home;
      person.squad = localSquad;
    }
    for (final person in remote) {
      person.location = camp;
      person.base = camp;
      person.squad = remoteSquad;
      person.body.torso.bleeding = 1;
      person.justEscaped = true;
    }
    patient.location = hospital;
    patient.base = home;
    patient.blood = patient.maxBlood - 20;
    patient.body.torso.bleeding = 1;
    patient.medicalBills = 135;
    patient.daysHospitalized = 2;
    patient.justEscaped = true;
    home.controller = SiteController.lcs;
    home.rent = 100;
    home.siege.activeSiegeType = SiegeType.police;
    home.siege.underAttack = false;
    home.compound.fortified = true;
    home.compound.rations = 100;
    home.loot.add(Weapon('WEAPON_COMBATKNIFE'));
    localSquad.loot.add(Ammo('CLIP_38', stackSize: 6));
    remoteSquad.loot.add(Ammo('CLIP_38', stackSize: 9));
    parkedLocal = Vehicle(VehicleTypeIds.van)..location = home;
    parkedRemote = Vehicle(VehicleTypeIds.sportsCar)..location = camp;
    game.vehiclePool.addAll([parkedLocal, parkedRemote]);
    game.activeSquad = localSquad;
    game.activeSite = home;
    game.activeSafehouse = home;
    game.activeSquadMemberIndex = -1;
    game.ledger.forceSetFunds(1000);
  }

  late final Site home, camp, hospital;
  late final List<Creature> local, remote;
  late final Creature patient;
  late final Squad localSquad, remoteSquad;
  late final Vehicle parkedLocal, parkedRemote;

  List<String> outsiders() => [
    _person(patient),
    ...remote.map(_person),
    _team(remoteSquad),
    jsonEncode(parkedRemote.toJson()),
  ];

  void expectOutsiders(List<String> before) {
    expect(outsiders(), before);
    expect(patient.hospitalized, isTrue);
    expect(patient.justEscaped, isTrue);
    expect(remote.every((p) => p.justEscaped), isTrue);
  }

  Creature reserve() {
    final person = Creature.fromJson(
      jsonDecode(jsonEncode(local.last.toJson())) as Map<String, dynamic>,
    );
    person.id = game.gameState.nextCreatureId++;
    person.name = 'Local reserve';
    person.squadId = null;
    person.body.torso.bleeding = 1;
    person.justEscaped = true;
    game.pool.add(person);
    return person;
  }
}

/// Stop after the actual source has selected and published its first field
/// decision. This tests preparation without pretending to finish the battle.
class _FirstSiegeDecision extends Console {
  final stopped = StateError('First prepared siege decision reached');

  @override
  Future<KeyEvent> getKeyEvent() async {
    if (screen == 'pursuit' || screen == 'tactical') throw stopped;
    return super.getKeyEvent();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    game.mode = GameMode.base;
    reseedRNG(seed: 20261017);
  });

  for (final tactical in [false, true]) {
    test(
      'siege preparation chooses local defenders with tactical $tactical',
      () async {
        final campaign = _SiegeCampaign();
        final outside = campaign.outsiders();
        campaign.home.siege.underAttack = tactical;
        game.activeSquad = campaign.remoteSquad;
        final stop = _FirstSiegeDecision();
        engine.console = stop;
        void acknowledge() {
          if (stop.awaitingInput && stop.eventMessage != null) {
            stop.sendInput('Enter');
          }
        }

        stop.revision.addListener(acknowledge);
        try {
          await expectLater(
            tactical
                ? siege.escapeOrEngage()
                : siege.sallyForthPart2(campaign.home),
            throwsA(same(stop.stopped)),
          );
        } finally {
          stop.revision.removeListener(acknowledge);
        }
        expect(game.activeSquad, same(campaign.localSquad));
        expect(game.squad.every((p) => p.location == campaign.home), isTrue);
        expect(game.squad, isNot(contains(campaign.patient)));
        campaign.expectOutsiders(outside);
      },
    );
  }

  test(
    'police surrender captures only present wanted crew and confiscates only local stock',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      campaign.local.first.wantedForCrimes[Crime.theft] = 1;
      await playChoices(() => giveUp(campaign.home), (_, _, _) => 'Enter');
      expect(campaign.home.siege.underSiege, isFalse);
      expect(campaign.home.controller, SiteController.unaligned);
      expect(campaign.home.loot, isEmpty);
      expect(campaign.home.compound.fortified, isFalse);
      expect(campaign.localSquad.loot, isEmpty);
      expect(campaign.local.first.imprisoned, isTrue);
      expect(campaign.local.first.squad, isNull);
      expect(campaign.local.last.location, same(campaign.home));
      expect(campaign.local.last.imprisoned, isFalse);
      for (final person in campaign.local) {
        expect(person.equippedWeapon, isNull);
        expect(person.spareAmmo, isNull);
      }
      expect(game.vehiclePool, isNot(contains(campaign.parkedLocal)));
      expect(game.vehiclePool, contains(campaign.parkedRemote));
      expect(game.ledger.funds, 1000);
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'a patient discharged after losing their rented home uses the existing camp fallback',
    () async {
      final campaign = _SiegeCampaign();
      await playChoices(() => giveUp(campaign.home), (_, _, _) => 'Enter');
      expect(campaign.patient.location, same(campaign.hospital));
      expect(campaign.patient.base, same(campaign.home));
      expect(campaign.home.controller, SiteController.unaligned);
      // The separate prepared discharge reader exercises relocation, not earned
      // healing; daily eligibility and actual treatment have their own tests.
      await playChoices(
        () => dischargeHospitalPatient(campaign.patient),
        (_, _, _) => 'b',
      );
      expect(campaign.patient.location, same(campaign.camp));
      expect(campaign.patient.base, same(campaign.camp));
      expect(campaign.patient.medicalBills, 135);
      expect(campaign.patient.daysHospitalized, 0);
    },
  );

  test(
    'siege evacuation preserves carried gear and driven cars, losing parked local stock',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final equipment = campaign.local.map(_equipment).toList();
      final driven = Vehicle(VehicleTypeIds.sportsCar)
        ..location = campaign.home;
      game.vehiclePool.add(driven);
      for (final person in campaign.local) {
        person.carId = driven.id;
        person.isDriver = person == campaign.local.first;
      }
      game.chaseSequence = ChaseSequence(campaign.home)..friendcar = [driven];
      await playChoices(() => siege.escapeSiege(false), (_, _, _) => 'Enter');
      expect(campaign.home.siege.underSiege, isFalse);
      expect(campaign.home.controller, SiteController.unaligned);
      expect(campaign.home.loot, isEmpty);
      expect(campaign.home.compound.rations, 0);
      expect(campaign.home.compound.fortified, isFalse);
      expect(campaign.localSquad.loot, isEmpty);
      expect(
        campaign.camp.loot.any((item) => item.typeName == 'CLIP_38'),
        isTrue,
      );
      expect(game.vehiclePool, contains(driven));
      expect(driven.location, same(campaign.camp));
      expect(game.vehiclePool, isNot(contains(campaign.parkedLocal)));
      for (final person in campaign.local) {
        expect(person.location, isNull);
        expect(person.base, same(campaign.camp));
        expect(person.squad, isNull);
        expect(person.hidingDaysLeft, inInclusiveRange(2, 4));
      }
      expect(campaign.local.map(_equipment), equipment);
      expect(game.ledger.funds, 1000);
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'winning the siege retains the safehouse and escalates only its police response',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final crew = campaign.local.map(_person).toList();
      final gear = jsonEncode(
        campaign.home.loot.map((item) => item.toJson()).toList(),
      );
      final heat = campaign.home.heat;
      await siege.escapeSiege(true);
      expect(campaign.home.siege.underSiege, isFalse);
      expect(
        campaign.home.siege.escalationState,
        SiegeEscalation.nationalGuard,
      );
      expect(campaign.home.heat, heat + 1000);
      expect(campaign.home.controller, SiteController.lcs);
      expect(campaign.local.map(_person), crew);
      expect(
        jsonEncode(campaign.home.loot.map((item) => item.toJson()).toList()),
        gear,
      );
      expect(game.vehiclePool, contains(campaign.parkedLocal));
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'hostile surrender kills present crew once and leaves hospital and remote crew alone',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      campaign.home.rent = 0;
      campaign.home.siege.activeSiegeType = SiegeType.ccs;
      final martyrs = game.stats.martyrs;
      await playChoices(() => giveUp(campaign.home), (_, _, _) => 'Enter');
      expect(campaign.home.controller, SiteController.ccs);
      expect(campaign.home.siege.underSiege, isFalse);
      expect(game.stats.martyrs, martyrs + campaign.local.length);
      for (final person in campaign.local) {
        expect(person.alive, isFalse);
        expect(person.location, isNull);
        expect(person.squad, isNull);
      }
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'original foot victory stops local bleeding without treating offsite patients or squads',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      campaign.local.first.body.torso.bleeding = 1;
      final reserve = campaign.reserve();
      game.chaseSequence = ChaseSequence(campaign.home);
      game.encounter.add(Creature.fromId(CreatureTypeIds.cop));
      ChaseOutcome? outcome;
      await playChoices(
        () async {
          outcome = await footChaseSequence(showStandardText: false);
        },
        (_, actions, _) => engine.console.screen == 'pursuit' ? 'f' : 'Enter',
        promptLimit: 200,
      );
      expect(outcome, ChaseOutcome.victory);
      expect(campaign.local.any((p) => p.alive), isTrue);
      expect(reserve.body.torso.bleeding, 0);
      for (final person in campaign.local) {
        expect(person.body.parts.every((part) => part.bleeding == 0), isTrue);
      }
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'pursuit custody stabilizes its own crew after their squad membership is removed',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      campaign.local.first.body.torso.bleeding = 2;
      game.chaseSequence = ChaseSequence(campaign.home)..canpullover = true;
      game.encounter.add(Creature.fromId(CreatureTypeIds.cop));
      await playChoices(() async {
        expect(
          await footChaseSequence(showStandardText: false),
          ChaseOutcome.capture,
        );
      }, (_, _, _) => engine.console.screen == 'pursuit' ? 'g' : 'Enter');
      expect(campaign.local.first.squad, isNull);
      expect(campaign.local.first.imprisoned, isTrue);
      expect(campaign.local.first.body.torso.bleeding, 0);
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'squad return includes hauled people and local reserves, preserving offsite escape flags',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final reserve = campaign.reserve();
      final hauled = campaign.reserve()..name = 'Hauled ally';
      campaign.local.first.prisoner = hauled;
      for (final person in campaign.local) {
        person.body.torso.bleeding = 1;
        person.justEscaped = true;
      }
      await squadCleanup();
      expect(campaign.local.first.prisoner, isNull);
      expect(hauled.location, same(campaign.home));
      expect(hauled.squad, isNull);
      for (final person in [...campaign.local, reserve, hauled]) {
        expect(person.body.torso.bleeding, 0);
        expect(person.justEscaped, isFalse);
      }
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'a separate street surrender does not clean a stale besieged active site',
    () async {
      final campaign = _SiegeCampaign();
      campaign.local.first.body.torso.bleeding = 1;
      final local = campaign.local.map(_person).toList();
      final patient = _person(campaign.patient);
      game.activeSquad = campaign.remoteSquad;
      game.chaseSequence = ChaseSequence(campaign.camp.district)
        ..canpullover = true;
      game.encounter.add(Creature.fromId(CreatureTypeIds.cop));
      await playChoices(() async {
        expect(
          await footChaseSequence(showStandardText: false),
          ChaseOutcome.capture,
        );
      }, (_, _, _) => engine.console.screen == 'pursuit' ? 'g' : 'Enter');
      expect(campaign.local.map(_person), local);
      expect(_person(campaign.patient), patient);
      expect(campaign.local.first.body.torso.bleeding, 1);
      expect(campaign.remote.every((person) => person.imprisoned), isTrue);
      expect(
        campaign.remote.every((person) => person.body.torso.bleeding == 0),
        isTrue,
      );
    },
  );

  test(
    'an uncarried siege casualty has no dangling saved squad after its group is removed',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final casualty = campaign.local.last;
      // The sole surviving carrier already has someone to carry. This prepared
      // casualty exercises the same original hauling reader as a failed breakout.
      campaign.local.first.prisoner = Creature.fromId(CreatureTypeIds.hippie);
      casualty.die();
      final martyrs = game.stats.martyrs;
      await playChoices(
        () => squadHaulImmobileAllies(true),
        (_, _, _) => 'Enter',
      );
      expect(casualty.location, isNull);
      expect(campaign.localSquad.members, isNot(contains(casualty)));
      expect(casualty.squadId, isNull);
      expect(game.stats.martyrs, martyrs);
      campaign.expectOutsiders(outside);
      campaign.local.first.squad = null;
      cleanGoneSquads();
      expect(game.squads, isNot(contains(campaign.localSquad)));
      final saved = jsonEncode(game.gameState.toJson());
      game.gameState = game.GameState.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
      final reloaded = game.pool.singleWhere(
        (person) => person.id == casualty.id,
      );
      expect(reloaded.squadId, isNull);
      expect(reloaded.squad, isNull);
      expect(reloaded.alive, isFalse);
      expect(reloaded.location, isNull);
    },
  );

  test(
    'siege promotion clears dead reverse membership while enlisting only local reserves',
    () {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final casualty = campaign.local.last;
      final reserves = [campaign.reserve(), campaign.reserve()];
      casualty.die();
      autopromote(campaign.home);
      expect(campaign.localSquad.members, isNot(contains(casualty)));
      expect(casualty.squadId, isNull);
      expect(campaign.localSquad.members, containsAll(reserves));
      expect(
        reserves.every((person) => person.squad == campaign.localSquad),
        isTrue,
      );
      campaign.expectOutsiders(outside);
    },
  );

  test(
    'a fatal car crash removes both sides of the dead occupant squad link',
    () async {
      final campaign = _SiegeCampaign();
      final outside = campaign.outsiders();
      final casualty = campaign.local.last;
      final car = Vehicle(VehicleTypeIds.sportsCar)..location = campaign.home;
      game.vehiclePool.add(car);
      casualty.carId = car.id;
      casualty.isDriver = true;
      casualty.blood = 1;
      game.chaseSequence = ChaseSequence(campaign.home)..friendcar = [car];
      game.mode = GameMode.carChase;
      final martyrs = game.stats.martyrs;
      await playChoices(() => crashfriendlycar(car), (_, _, _) => 'Enter');
      expect(casualty.alive, isFalse);
      expect(campaign.localSquad.members, isNot(contains(casualty)));
      expect(casualty.squadId, isNull);
      expect(game.stats.martyrs, martyrs + 1);
      expect(game.vehiclePool, isNot(contains(car)));
      expect(campaign.local.first.alive, isTrue);
      campaign.expectOutsiders(outside);
    },
  );
}
