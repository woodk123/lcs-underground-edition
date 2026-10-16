import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

/// These engine-only fixtures deliberately prepare strong or critical actors
/// to reach cleanup boundaries. Browser journeys use unchanged original crew.
Vehicle _carFor(Creature person, {bool slow = false}) {
  final car = Vehicle(slow ? VehicleTypeIds.bug : VehicleTypeIds.sportsCar)
    ..location = person.base;
  game.vehiclePool.add(car);
  person.preferredCarId = car.id;
  person.preferredDriver = true;
  return car;
}

String _saved(Creature person) => jsonEncode(person.toJson());

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
    game.activeSite = game.squad.first.site;
    game.activeSquadMemberIndex = -1;
    game.sitestory = null;
    for (final person in game.pool) {
      person.wantedForCrimes.updateAll((crime, count) => 0);
      person.activity = Activity.none();
    }
    reseedRNG(seed: 20261016);
  });

  test(
    'real bailout switches readers, rejects retained car controls and escapes on foot',
    () async {
      final person = game.squad.last;
      // A prepared fast runner reaches the successful on-foot cleanup reliably.
      person.rawAttributes[Attribute.agility] = 50;
      final car = _carFor(person);
      final parked = Vehicle(VehicleTypeIds.van)..location = person.base;
      game.vehiclePool.add(parked);
      final originalSquad = game.activeSquad!;
      final squads = List.of(game.squads);
      final founder = _saved(game.pool.first);
      final equipment = jsonEncode([
        person.equippedWeapon?.toJson(),
        person.spareAmmo?.toJson(),
      ]);
      final portrait = person.portraitId;
      PursuitContext? carFrame;
      ConsoleAction? oldBailout, oldFight;
      var carReaders = 0, footReaders = 0;
      ChaseOutcome? outcome;
      await playChoices(
        () async {
          outcome = await soloChaseSequence(person, 1, v: car);
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) return 'Enter';
          if (frame.title == 'Car pursuit') {
            carReaders++;
            carFrame = frame;
            oldBailout = frame.actions.singleWhere(
              (action) => action.key == 'b',
            );
            oldFight = frame.actions.singleWhere((action) => action.key == 'f');
            expect(
              pursuitActionIsCurrent(
                engine.console,
                frame,
                oldBailout!,
                engine.console.revision.value,
              ),
              isTrue,
            );
            return oldBailout!.key;
          }
          footReaders++;
          expect(frame.title, 'On-foot pursuit');
          expect(frame, isNot(same(carFrame)));
          expect(
            frame.actions.map((action) => action.key),
            isNot(contains('b')),
          );
          expect(
            frame.actions.map((action) => action.key),
            isNot(contains('p')),
          );
          expect(
            pursuitActionIsCurrent(
              engine.console,
              carFrame!,
              oldBailout!,
              engine.console.revision.value,
            ),
            isFalse,
          );
          expect(
            pursuitActionIsCurrent(
              engine.console,
              carFrame!,
              oldFight!,
              engine.console.revision.value,
            ),
            isFalse,
          );
          expect(game.vehiclePool, isNot(contains(car)));
          expect(person.car, isNull);
          expect(
            frame.actions.singleWhere((action) => action.key == 'd').enabled,
            isTrue,
          );
          return 'd';
        },
      );
      expect(carReaders, 1);
      expect(footReaders, greaterThan(0));
      expect(outcome, ChaseOutcome.escape);
      expect(person.alive, isTrue);
      expect(person.squad, same(originalSquad));
      expect(person.location, person.base);
      expect(game.activeSquad, same(originalSquad));
      expect(game.squads, squads);
      expect(game.vehiclePool, [parked]);
      expect(person.portraitId, portrait);
      expect(
        jsonEncode([
          person.equippedWeapon?.toJson(),
          person.spareAmmo?.toJson(),
        ]),
        equipment,
      );
      expect(_saved(game.pool.first), founder);
      expect(game.mode, GameMode.base);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      roundTripLiveCampaign();
    },
  );

  test(
    'repeated original car combat resolves without choosing escape or surrender',
    () async {
      final person = game.squad.last;
      person.rawAttributes.updateAll(
        (attribute, value) => attribute == Attribute.wisdom ? 1 : 50,
      );
      person.rawSkill.updateAll((skill, value) => 50);
      person.juice = 1000;
      person.giveWeaponAndAmmo('WEAPON_AK102', 8);
      final car = _carFor(person);
      final originalSquad = game.activeSquad!;
      final squads = List.of(game.squads);
      final founder = _saved(game.pool.first);
      final ammo = person.weapon.ammo;
      var fights = 0, obstacleResponses = 0;
      ChaseOutcome? outcome;
      final frames = await playChoices(
        () async {
          outcome = await soloChaseSequence(person, 1, v: car);
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) return 'Enter';
          final action = frame.actions.singleWhere(
            (action) => action.key == 'f',
          );
          if (frame.title == 'Car pursuit' &&
              action.intentLabel == 'Slow down') {
            obstacleResponses++;
          } else {
            fights++;
          }
          expect(action.enabled, isTrue);
          return action.key;
        },
        promptLimit: 300,
      );
      expect(fights, greaterThan(0));
      expect(fights + obstacleResponses, greaterThan(0));
      expect(frames.join('\n'), contains('open fire'));
      expect(outcome!.won, isTrue);
      expect(person.alive, isTrue);
      expect(person.weapon.ammo, lessThan(ammo));
      expect(person.squad, same(originalSquad));
      expect(game.activeSquad, same(originalSquad));
      expect(game.squads, squads);
      expect(game.vehiclePool, contains(car));
      expect(
        game.encounter.where((enemy) => enemy.isEnemy && enemy.alive),
        isEmpty,
      );
      expect(game.chaseSequence!.enemyCarDistance, isEmpty);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      expect(_saved(game.pool.first), founder);
      roundTripLiveCampaign();
    },
  );

  test(
    'actual combat death cleans the temporary solo squad and records one martyr',
    () async {
      final person = game.squad.last;
      // A living but critical, stunned unarmed driver exercises real enemy rounds
      // and crashes, rather than entering the handler with an already dead crew.
      person.rawAttributes.updateAll((attribute, value) => 1);
      person.rawSkill.updateAll((skill, value) => 0);
      person.blood = 1;
      person.stunned = 50;
      person.equippedWeapon = null;
      person.spareAmmo = null;
      person.equippedClothing = null;
      final car = _carFor(person, slow: true);
      final originalSquad = game.activeSquad!;
      final squads = List.of(game.squads);
      final founder = _saved(game.pool.first);
      final martyrs = game.stats.martyrs;
      var fights = 0, reflections = 0;
      ChaseOutcome? outcome;
      final frames = await playChoices(
        () async {
          outcome = await soloChaseSequence(person, 1, v: car);
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) return 'Enter';
          final reflection = frame.actions
              .where((action) => action.key == 'c')
              .firstOrNull;
          if (reflection != null) {
            reflections++;
            return reflection.key;
          }
          fights++;
          return frame.actions.singleWhere((action) => action.key == 'f').key;
        },
        promptLimit: 300,
      );
      expect(fights, greaterThan(0));
      expect(reflections, 1);
      expect(frames.join('\n'), contains('open fire'));
      expect(outcome, ChaseOutcome.death);
      expect(person.alive, isFalse);
      expect(person.location, isNull);
      // This declared critical fixture reaches direct car defeat: the body
      // remains in the campaign, unlike an unrecovered body lost on foot.
      expect(game.pool, contains(person));
      expect(
        person.squadId,
        isNull,
        reason:
            'The removed temporary pursuit squad must not remain attached to its dead member.',
      );
      expect(originalSquad.members, isNot(contains(person)));
      expect(game.activeSquad, same(originalSquad));
      expect(game.squads, squads);
      expect(game.vehiclePool, isNot(contains(car)));
      expect(game.stats.martyrs, martyrs + 1);
      expect(game.mode, GameMode.base);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      expect(_saved(game.pool.first), founder);
      roundTripLiveCampaign();
      final restored = game.pool.singleWhere(
        (candidate) => candidate.id == person.id,
      );
      expect(restored.alive, isFalse);
      expect(restored.squadId, isNull);
    },
  );
}
