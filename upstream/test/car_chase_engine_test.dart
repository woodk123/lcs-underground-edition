import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

void _prepareCars({bool armed = false}) {
  final car = Vehicle(VehicleTypeIds.sportsCar)
    ..location = game.squad.first.site;
  game.vehiclePool.add(car);
  for (final person in game.squad) {
    person.carId = car.id;
    person.isDriver = person == game.squad.first;
    person.rawSkill[Skill.driving] = 50;
    if (armed) {
      person.rawAttributes.updateAll((a, v) => a == Attribute.wisdom ? 1 : 50);
      person.rawSkill.updateAll((s, v) => 50);
      person.juice = 1000;
      person.giveWeaponAndAmmo('WEAPON_M250_MACHINEGUN', 20);
      person.giveArmor(Clothing('CLOTHING_HEAVYARMOR'));
    }
  }
  game.chaseSequence = ChaseSequence(game.squad.first.site!);
  makeChasers(SiteType.policeStation, 1);
}

PursuitContext _animationFrame() => PursuitContext(
  title: 'Car pursuit',
  location: 'Animation regression',
  note: '',
  people: const [],
  encounterLines: const [],
  actions: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
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
    'original driving escape retains cars and records resisting arrest',
    () async {
      _prepareCars();
      final crew = List<Creature>.of(game.squad);
      final car = crew.first.car!;
      ChaseOutcome? outcome;
      var drivingReaders = 0;
      await playChoices(
        () async {
          outcome = await carChaseSequence();
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) return 'Enter';
          expect(frame.title, 'Car pursuit');
          expect(frame.statusLines, isNotEmpty);
          expect(frame.encounterLines, isNotEmpty);
          drivingReaders++;
          return 'd';
        },
      );
      expect(drivingReaders, greaterThan(0));
      expect(outcome, ChaseOutcome.escape);
      expect(game.vehiclePool, contains(car));
      expect(crew.every((p) => p.car == car), isTrue);
      expect(
        crew.every((p) => p.wantedForCrimes[Crime.resistingArrest]! > 0),
        isTrue,
      );
      expect(game.mode, GameMode.base);
      expect(game.chaseSequence!.enemyCarDistance, isEmpty);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      roundTripLiveCampaign();
    },
  );

  test(
    'original car combat consumes ammunition and can complete an escape',
    () async {
      _prepareCars(armed: true);
      final crew = List<Creature>.of(game.squad);
      final ammo = crew.fold(0, (n, p) => n + p.weapon.ammo);
      final car = crew.first.car!;
      var fought = false;
      ChaseOutcome? outcome;
      final frames = await playChoices(
        () async {
          outcome = await carChaseSequence();
        },
        (_, actions, _) {
          if (pursuitContext(engine.console) == null) return 'Enter';
          if (!fought) {
            fought = true;
            return 'f';
          }
          return 'd';
        },
        promptLimit: 250,
      );
      expect(fought, isTrue);
      expect(outcome!.won, isTrue);
      expect(frames.join('\n'), contains('open fire'));
      expect(crew.fold(0, (n, p) => n + p.weapon.ammo), lessThan(ammo));
      expect(game.vehiclePool, contains(car));
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      roundTripLiveCampaign();
    },
  );

  test(
    'car surrender confiscates convoy and equipment but retains parked cars',
    () async {
      _prepareCars();
      final crew = List<Creature>.of(game.squad);
      final convoy = crew.first.car!;
      final portraits = crew.map((p) => p.portraitId).toList();
      final parked = Vehicle(VehicleTypeIds.van)..location = game.activeSite;
      game.vehiclePool.add(parked);
      ChaseOutcome? outcome;
      await playChoices(
        () async {
          outcome = await carChaseSequence();
        },
        (_, actions, _) =>
            pursuitContext(engine.console) == null ? 'Enter' : 'p',
      );
      expect(outcome, ChaseOutcome.capture);
      expect(game.vehiclePool, isNot(contains(convoy)));
      expect(game.vehiclePool, contains(parked));
      for (final person in crew) {
        expect(person.imprisoned, isTrue);
        expect(person.site!.type, SiteType.policeStation);
        expect(person.squad, isNull);
        expect(person.carId, isNull);
        expect(person.equippedWeapon, isNull);
        expect(person.spareAmmo, isNull);
        expect(person.activity.type, ActivityType.none);
        expect(person.wantedForCrimes[Crime.resistingArrest], 0);
      }
      expect(crew.map((p) => p.portraitId), portraits);
      expect(game.mode, GameMode.base);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
      roundTripLiveCampaign();
    },
  );

  test(
    'car retries and nested equipment publish fresh exact controls',
    () async {
      _prepareCars();
      var readers = 0, equipmentReaders = 0;
      late PursuitContext previous;
      late ConsoleAction previousPullOver;
      await playChoices(
        () async {
          await carChaseSequence();
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) {
            if (engine.console.eventMessage == null) {
              equipmentReaders++;
              expect(engine.console.pursuit, isNull);
              expect(actions.any((a) => a.key == 'p'), isFalse);
            }
            return 'Enter';
          }
          expect(
            frame.actions.map((a) => a.key),
            containsAll(['d', 'f', 'e', 'o', 'b', 'p', '0', '1', '2']),
          );
          expect(
            frame.actions.singleWhere((a) => a.key == 'o').enabled,
            isTrue,
          );
          final pullOver = frame.actions.singleWhere((a) => a.key == 'p');
          expect(
            pursuitActionIsCurrent(
              engine.console,
              frame,
              pullOver,
              engine.console.revision.value,
            ),
            isTrue,
          );
          if (readers++ > 0) {
            expect(identical(frame, previous), isFalse);
            expect(frame.actions.contains(previousPullOver), isFalse);
            expect(
              pursuitActionIsCurrent(
                engine.console,
                previous,
                previousPullOver,
                engine.console.revision.value,
              ),
              isFalse,
            );
          }
          previous = frame;
          previousPullOver = pullOver;
          return switch (readers) {
            1 => '?',
            2 => 'e',
            _ => 'p',
          };
        },
      );
      expect(readers, 3);
      expect(equipmentReaders, 1);
    },
  );

  test('obstacle labels expose accepted support and surrender controls', () {
    _prepareCars();
    printCarChaseOptions(
      dOption: '-Swerve into an alley',
      fOption: '-Slow down',
      gOption: '-Smash through',
    );
    final actions = engine.console.actions;
    expect(
      actions.singleWhere((a) => a.key == 'd').intentLabel,
      'Swerve into an alley',
    );
    expect(actions.singleWhere((a) => a.key == 'f').intentLabel, 'Slow down');
    expect(
      actions.singleWhere((a) => a.key == 'g').intentLabel,
      'Smash through',
    );
    for (final key in ['d', 'f', 'g', 'e', 'o', 'b', 'p']) {
      expect(actions.singleWhere((a) => a.key == key).enabled, isTrue);
    }
    engine.erase();
    game.chaseSequence!.canpullover = false;
    printCarChaseOptions(dOption: '-Run the light', fOption: '-Slow down');
    expect(engine.console.actions.any((a) => a.key == 'g'), isFalse);
    expect(
      engine.console.actions.singleWhere((a) => a.key == 'p').enabled,
      isFalse,
    );
    expect(
      engine.console.actions.singleWhere((a) => a.key == 'b').enabled,
      isTrue,
    );
  });

  test('solo car pursuit introduction describes the current actor', () async {
    final person = game.squad.last;
    final oldSquad = person.squad;
    final oldActiveSquad = game.activeSquad;
    final car = Vehicle(VehicleTypeIds.sportsCar)..location = person.site;
    game.vehiclePool.add(car);
    var introduction = false;
    await playChoices(
      () async {
        expect(
          await soloChaseSequence(person, 1, v: car),
          ChaseOutcome.capture,
        );
      },
      (_, actions, _) {
        if (pursuitContext(engine.console) != null) return 'p';
        introduction |=
            engine.console.eventMessage?.contains(
              '${person.name} is being pursued by car.',
            ) ??
            false;
        return 'Enter';
      },
    );
    expect(introduction, isTrue);
    expect(game.activeSquad, same(oldActiveSquad));
    expect(oldSquad!.members, isNot(contains(person)));
  });

  test(
    'actual obstacle reader slows down and retains accepted surrender',
    () async {
      _prepareCars();
      // An unarmed pursuit at a declared longer distance permits the normal
      // random obstacle selection to run before either car drops out.
      for (final person in [...game.squad, ...game.encounter]) {
        person.equippedWeapon = null;
        person.spareAmmo = null;
      }
      game.chaseSequence!.enemyCarDistance.updateAll((v, d) => 30);
      var obstacleSeen = false, slowedDown = false;
      ChaseOutcome? outcome;
      await playChoices(
        () async {
          outcome = await carChaseSequence();
        },
        (_, actions, _) {
          final frame = pursuitContext(engine.console);
          if (frame == null) {
            slowedDown |=
                engine.console.eventMessage?.contains('You slow down and') ??
                false;
            return 'Enter';
          }
          if (obstacleSeen) return 'p';
          if (frame.actions.singleWhere((a) => a.key == 'f').intentLabel ==
              'Slow down') {
            obstacleSeen = true;
            for (final key in ['e', 'o', 'b', 'p']) {
              expect(
                frame.actions.singleWhere((a) => a.key == key).enabled,
                isTrue,
              );
            }
          }
          return 'f';
        },
        promptLimit: 250,
      );
      expect(obstacleSeen, isTrue);
      expect(slowedDown, isTrue);
      expect(outcome, ChaseOutcome.capture);
    },
  );

  test('enemy obstacle crash works without a site story', () async {
    _prepareCars();
    game.chaseSequence!.friendcar = [game.squad.first.car!];
    for (final enemy in game.encounter) {
      enemy.rawSkill[Skill.driving] = -100;
    }
    final enemyCar = game.chaseSequence!.enemycar.single;
    await playChoices(() async {
      expect(await dodgedrive(), isFalse);
    }, (_, _, _) => 'Enter');
    expect(game.sitestory, isNull);
    expect(game.chaseSequence!.enemycar, isNot(contains(enemyCar)));
    expect(game.chaseSequence!.enemyCarDistance.containsKey(enemyCar), isFalse);
    expect(game.encounter, isEmpty);
  });

  test(
    'backing off removes both the enemy car and its target distance',
    () async {
      _prepareCars();
      final car = game.chaseSequence!.enemycar.single;
      await playChoices(() => backOffEnemyCar(car), (_, _, _) => 'Enter');
      expect(game.chaseSequence!.enemycar, isEmpty);
      expect(game.chaseSequence!.enemyCarDistance, isEmpty);
      expect(game.encounter, isEmpty);
    },
  );

  Future<void> withAnimation(
    Future<void> Function(Console, CarChaseAnimation) inspect,
  ) async {
    _prepareCars();
    game.mode = GameMode.carChase;
    final console = engine.console;
    console.screen = 'pursuit';
    console.pursuit = _animationFrame();
    final reader = console.getKeyEvent();
    final animation = game.chaseSequence!.chaseAnimation;
    final task = animation.animate();
    try {
      await inspect(console, animation);
    } finally {
      animation.stop();
      console.sendInput('Enter');
      await reader;
      await task;
    }
  }

  test(
    'cosmetic frames preserve campaign RNG and the current input revision',
    () async {
      _prepareCars();
      // Preparing cars consumes engine rolls; compare only animation itself.
      reseedRNG(seed: 901);
      final expected = lcsRandom(1000000);
      await withAnimation((console, animation) async {
        reseedRNG(seed: 901);
        final revision = console.revision.value;
        final state = jsonEncode(game.gameState.toJson());
        var repaints = 0;
        console.repaint = () => repaints++;
        await Future<void>.delayed(const Duration(milliseconds: 240));
        expect(repaints, inInclusiveRange(2, 5));
        expect(console.revision.value, revision);
        expect(jsonEncode(game.gameState.toJson()), state);
        expect(lcsRandom(1000000), expected);
      });
    },
  );

  test(
    'overlapping enemy cars at the left edge do not index outside console',
    () async {
      await withAnimation((console, animation) async {
        final chase = game.chaseSequence!;
        final extra = Vehicle(VehicleTypeIds.policeCar);
        chase.enemycar.add(extra);
        for (final car in chase.enemycar) {
          chase.enemyCarDistance[car] = 60;
          animation.enemyCarShownPosition[car] = 60;
        }
        await Future<void>.delayed(const Duration(milliseconds: 90));
        expect(console.buffer[23].first.glyph, 'o');
        expect(console.awaitingInput, isTrue);
      });
    },
  );

  test(
    'animation leaves nested equipment and replaced console untouched',
    () async {
      await withAnimation((console, animation) async {
        engine.erase();
        engine.mvaddstr(23, 0, 'Nested equipment owns this line');
        final line = console.buffer[23].map((c) => c.glyph).join();
        final revision = console.revision.value;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(console.buffer[23].map((c) => c.glyph).join(), line);
        expect(console.revision.value, revision);
        final replacement = Console();
        engine.console = replacement;
        replacement.move(23, 0);
        replacement.addstr('Replacement reader');
        final nextLine = replacement.buffer[23].map((c) => c.glyph).join();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(replacement.buffer[23].map((c) => c.glyph).join(), nextLine);
        expect(replacement.revision.value, 0);
      });
    },
  );

  test(
    'car sequence stops animation when a source input listener fails',
    () async {
      _prepareCars();
      final failure = StateError('forced reader failure');
      // A source observer cannot throw through ValueNotifier; inject the failure
      // through the existing repaint callback after the original reader awaits.
      var reports = 0;
      engine.console.revision.addListener(() {
        if (engine.console.eventMessage != null &&
            engine.console.awaitingInput) {
          reports++;
          engine.console.sendInput('Enter');
        }
      });
      engine.console.repaint = () {
        if (pursuitContext(engine.console) != null) throw failure;
      };
      // The source getKey flush calls repaint synchronously, so its exception
      // unwinds carChaseSequence through the same finally as gameplay failures.
      await expectLater(carChaseSequence(), throwsA(same(failure)));
      expect(reports, 1);
      expect(game.chaseSequence!.chaseAnimation.halting, isTrue);
    },
  );
}
