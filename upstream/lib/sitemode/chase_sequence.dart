import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/common_display/print_party.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/conversion.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/difficulty.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console_char.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/sitemode/advance.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/haul_kidnap.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/miscactions.dart';
import 'package:lcs_new_age/sitemode/operation_cleanup.dart';
import 'package:lcs_new_age/sitemode/site_display.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

class ChaseSequence {
  ChaseSequence(this.location);
  Location location;
  late CarChaseAnimation chaseAnimation = CarChaseAnimation(this);
  Site? get site => location is Site ? location as Site : null;
  List<Vehicle> friendcar = [];
  List<Vehicle> enemycar = [];
  Map<Vehicle, int> enemyCarDistance = {};
  bool canpullover = false;
  int turn = 0;
  void clean() {
    turn = 0;
    enemycar.clear();
    friendcar.clear();
    enemyCarDistance.clear();
    chaseAnimation.stop();
  }

  void crash() {
    enemyCarDistance.updateAll((v, d) => lcsRandom(7) - 3);
    chaseAnimation.crash();
  }
}

class CarChaseAnimation {
  CarChaseAnimation(ChaseSequence chaseSequence)
    : _chaseSequence = WeakReference(chaseSequence);
  final WeakReference<ChaseSequence> _chaseSequence;
  ChaseSequence get chaseSequence => _chaseSequence.target!;
  Map<Vehicle, int> enemyCarAnimationPhase = {};
  Map<Vehicle, int> enemyCarShownPosition = {};
  bool halting = false;
  bool crashed = false;
  int _generation = 0;

  void stop() {
    halting = true;
    _generation++;
  }

  void crash() {
    crashed = true;
  }

  Future<void> animate() async {
    final inputConsole = console;
    final chase = _chaseSequence.target;
    if (chase == null) return;
    final generation = ++_generation;
    // Cosmetic police lights must not consume campaign random rolls.
    enemyCarAnimationPhase = {
      for (final vehicle in chase.enemycar) vehicle: vehicle.id % 6,
    };
    enemyCarShownPosition = {
      for (final vehicle in chase.enemycar)
        vehicle: chase.enemyCarDistance[vehicle] ?? 70,
    };
    halting = false;
    crashed = false;
    final stopwatch = Stopwatch()..start();
    var crashedT = 0;

    while (!halting &&
        generation == _generation &&
        identical(console, inputConsole) &&
        mode == GameMode.carChase) {
      // A nested equipment, dossier or report reader owns the entire console.
      // Only paint the road while this exact source decision is waiting.
      if (inputConsole.awaitingInput &&
          inputConsole.screen == 'pursuit' &&
          inputConsole.eventMessage == null &&
          inputConsole.pursuit?.title == 'Car pursuit') {
        var t = stopwatch.elapsedMilliseconds ~/ 75;
        if (crashed) {
          t = crashedT;
        } else {
          crashedT = t;
        }
        final strobeT = stopwatch.elapsedMilliseconds ~/ 150;
        // Write cosmetic cells directly: authored report tracking and the
        // source reader's cursor/color must remain untouched.
        for (var x = 0; x < inputConsole.width; x++) {
          inputConsole.buffer[23][x] =
              ConsoleChar((t + x) % 3 == 0 ? '_' : ' ', lightGray, black);
        }
        final yourCarX = 60 + chase.turn;
        if (yourCarX >= 0 && yourCarX < inputConsole.width) {
          inputConsole.buffer[23][yourCarX] = ConsoleChar('o', lightGreen, black);
        }
        for (final vehicle in chase.enemycar) {
          final shownXPos = enemyCarShownPosition[vehicle] ?? 71;
          final intendedXPos = chase.enemyCarDistance[vehicle] ?? 71;
          if (t % 3 == 0 || crashed || (shownXPos - intendedXPos).abs() > 5) {
            if (shownXPos > intendedXPos) {
              enemyCarShownPosition[vehicle] = max(intendedXPos, shownXPos - 1);
            } else if (shownXPos < intendedXPos) {
              enemyCarShownPosition[vehicle] = min(intendedXPos, shownXPos + 1);
            }
          }
          var x = yourCarX - shownXPos;
          if (x < 0 || x >= inputConsole.width) continue;
          while (x >= 0 && inputConsole.buffer[23][x].glyph == 'o') {
            x--;
          }
          if (x < 0) continue;
          final phase = (enemyCarAnimationPhase[vehicle] ?? 0) + strobeT;
          final Color color = vehicle.type.idName == VehicleTypeIds.policeCar
              ? switch (phase % 6) {
                  0 || 1 || 3 => blue,
                  _ => red,
                }
              : red;
          inputConsole.buffer[23][x] = ConsoleChar('o', color, black);
        }
        // A cosmetic frame changes neither the reader nor its action revision.
        inputConsole.stale = true;
        inputConsole.repaint?.call();
      }
      await Future<void>.delayed(
        Duration(milliseconds: 75 - stopwatch.elapsedMilliseconds % 75),
      );
    }
  }
}

enum CarChaseObstacles { fruitStand, truckPullsOut, crossTraffic, child }

int get partysize => squad.length;
int get partyalive => squad.where((s) => s.alive).length;

void printChaseOptions() {
  setColor(lightGray);
  addOptionText(10, 1, "D", "D-Try to lose them");
  addstr(", ");
  addInlineOptionText("F", "Fight");
  addstr(", ");
  addInlineOptionText("E", "Equip");
  addstr(", ");
  addInlineOptionText("O", "Order", enabledWhen: partysize > 1);
  addstr(", ");
  bool surrenderIsAnOption = chaseSequence?.canpullover ?? false;
  addInlineOptionText("G", "Give up", enabledWhen: surrenderIsAnOption);
}

void printCarChaseOptions({
  String dOption = "rive hard to escape",
  String fOption = "ight",
  String? gOption,
}) {
  setColor(lightGray);
  addOptionText(12, 1, "D", "D$dOption");
  addstr(", ");
  addInlineOptionText("F", "F$fOption");
  if (gOption != null) {
    addstr(", ");
    addInlineOptionText("G", "G$gOption");
  }
  console.annotateAction(
    'd',
    dOption.startsWith('-') ? dOption.substring(1) : 'D$dOption',
  );
  console.annotateAction(
    'f',
    fOption.startsWith('-') ? fOption.substring(1) : 'F$fOption',
  );
  if (gOption != null) {
    console.annotateAction(
      'g',
      gOption.startsWith('-') ? gOption.substring(1) : 'G$gOption',
    );
  }
  // These commands were already accepted by the original car reader, including
  // during obstacles. Keep them visible without changing their availability.
  addOptionText(22, 1, 'E', 'E-Equip');
  addstr(', ');
  addInlineOptionText('O', 'O-Orders', enabledWhen: partysize > 1);
  addstr(', ');
  addInlineOptionText('B', 'B-Bail out and run');
  addstr(', ');
  addInlineOptionText(
    'P',
    'P-Pull over and surrender',
    enabledWhen: chaseSequence!.canpullover,
  );
  console.annotateAction('e', 'Equipment');
  console.annotateAction('o', 'Squad orders');
  console.annotateAction('b', 'Bail out and run');
  console.annotateAction('p', 'Pull over and surrender');
}

Future<void> handleChaseSquadOptions(int c) async {
  if (c == Key.o && partysize > 1) await orderparty();
  if (c == Key.num0) activeSquadMemberIndex = -1;
  if (c >= Key.num1 && c <= Key.num6) {
    if (squad.length > c - Key.num1) {
      if (activeSquadMemberIndex == c - Key.num1) {
        await fullCreatureInfoScreen(activeSquadMember!);
      } else {
        activeSquadMemberIndex = c - Key.num1;
      }
    }
  }
}

Future<ChaseOutcome> carChaseSequence({String? introduction}) async {
  ChaseSequence chase = chaseSequence!;
  await reloadparty(false);

  //BAIL IF NO CHASERS
  if (encounter.isEmpty) return ChaseOutcome.victory;

  // Add unique cars to the friendcar list
  chase.friendcar = squad.map((p) => p.car).nonNulls.toSet().toList();

  mode = GameMode.carChase;

  erase();
  if (introduction != null) {
    mvaddstrc(0, 0, white, introduction);
  } else {
    mvaddstrc(
      0,
      0,
      white,
      "As you pull away from the site, you notice that you are ",
    );
    mvaddstr(1, 0, "being followed by Conservative swine!");
  }
  await acknowledge(title: 'Pursuit report');

  if (chase.location is Site) {
    chase.location = (chase.location as Site).district;
  }

  CarChaseObstacles? obstacle;

  int seed = lcsRandom(1000);
  final animation = chase.chaseAnimation;
  final animationTask = animation.animate();
  try {
    while (true) {
      erase();
      mvaddstrc(0, 0, lightGray, chaseSequence!.location.name);

      //PRINT PARTY
      if (partyalive == 0) activeSquadMemberIndex = -1;
      printParty();
      if (partyalive == 0) {
        //DESTROY ALL CARS BROUGHT ALONG WITH PARTY
        vehiclePool.removeWhere((v) => chaseSequence!.friendcar.contains(v));
        for (Creature p in squad) {
          p.die();
          p.location = null;
        }
        addOptionText(9, 1, "C", "C - Reflect on your Conservative driving.");
        printChaseEncounter();
        while (true) {
          _publishCarPursuit();
          if (await getKey() == Key.c) break;
          addOptionText(9, 1, 'C', 'C - Reflect on your Conservative driving.');
        }
        if (!await checkForDefeat()) {
          animation.stop();
          mode = GameMode.base;
          return ChaseOutcome.death;
        }
      }
      Vehicle nearestVehicle = chaseSequence!.enemyCarDistance.entries
          .reduce((a, b) => a.value < b.value ? a : b)
          .key;
      int nearestVehicleDistance = chase.enemyCarDistance[nearestVehicle] ?? 70;
      if (nearestVehicleDistance <= 0) {
        mvaddstrc(
          9,
          1,
          lightGray,
          "${nearestVehicle.fullName()} is right on your tail!",
        );
      } else {
        mvaddstrc(
          9,
          1,
          lightGray,
          "${nearestVehicle.fullName()} is ${nearestVehicleDistance * 5} feet back.",
        );
      }

      bool canDeliberatelyHit = false;
      if (obstacle == null) {
        if (chase.location.area > 0) {
          // Roar through the streets of the city
          mvaddstrc(
            10,
            1,
            lightGray,
            [
              "The roar of engines echoes through narrow alleys.",
              "You weave between cars as the pursuers tail you.",
              "Red lights blur past as you race down avenues.",
              "The pursuing headlights flash in your mirrors.",
              "With tires screeching, you cut through the city's veins.",
              "Skyscrapers loom above while engines roar below.",
              "Bright billboards flash by in a neon haze.",
              "Urban chaos surrounds you as the wheels scream.",
              "Your GPS won't stop saying 'Recalculating.'",
              "The lane markers are only suggestions to you.",
              "Pedestrians scramble to get out of your way.",
            ].randomSeeded(seed + chase.turn),
          );
        } else {
          // Outskirts car chase
          mvaddstrc(
            10,
            1,
            lightGray,
            [
              "The roar of engines echoes through the countryside.",
              "You barrel down a tree-lined street with pursuers behind.",
              "You are cruising through a suburban neighborhood.",
              "The pursuing headlights flash in your mirrors.",
              "Potholes shake everyone on a roughly maintained road.",
              "Rows of pastel houses stretch out on either side.",
              "The cracked asphalt of a surburban Main Street trembles.",
              "Signs say to slow down as you careen past a school zone.",
              "Rusty mailboxes shake on their posts as you speed by.",
              "The road is lined with trees, their branches a blur.",
              "You swerve past a tractor, its driver shouting curses.",
            ].randomSeeded(seed + chase.turn),
          );
        }
        printCarChaseOptions();
      } else {
        switch (obstacle) {
          case CarChaseObstacles.fruitStand:
            mvaddstrc(
              10,
              1,
              purple,
              "Street market ahead!  Flimsy fruit stands block the street.",
            );
            printCarChaseOptions(
              dOption: "-Swerve into an alley",
              fOption: "-Slow down",
              gOption: "-Smash through",
            );
            canDeliberatelyHit = true;
          case CarChaseObstacles.truckPullsOut:
            mvaddstrc(10, 1, purple, "A truck pulls out!");
            printCarChaseOptions(
              dOption: "-Swerve around",
              fOption: "-Slow down",
            );
          case CarChaseObstacles.crossTraffic:
            mvaddstrc(10, 1, purple, "Red light with cross traffic!");
            printCarChaseOptions(
              dOption: "-Run the light",
              fOption: "-Slow down",
            );
          case CarChaseObstacles.child:
            mvaddstrc(10, 1, purple, "A kid in the street!");
            printCarChaseOptions(
              dOption: "-Swerve into traffic",
              fOption: "-Slow down",
            );
        }
      }

      //PRINT ENEMIES
      printChaseEncounter();
      _publishCarPursuit();
      int c = await getKey();

      eraseLine(12);

      await handleChaseSquadOptions(c);
      bool timePassed = false;

      if (c == Key.e) {
        await equip(activeSquad!.loot);
      } else if (c == Key.b) {
        vehiclePool.removeWhere((v) => chaseSequence!.friendcar.contains(v));
        for (Creature p in squad) {
          p.carId = -1;
        }
        return await footChaseSequence();
      } else if (c == Key.p) {
        if (chaseSequence!.canpullover) {
          await chaseGiveUp();
          mode = GameMode.base;
          animation.stop();
          return ChaseOutcome.capture;
        }
      } else if (obstacle == null) {
        bool actionTaken = [Key.d, Key.f].contains(c);
        if (actionTaken) {
          if (encounter.any((e) => e.type.lawEnforcement)) {
            sitestory?.drama.add(Drama.carChase);
            criminalizeAll(squad, Crime.resistingArrest);
          }
          if (c == Key.d) {
            chase.turn++;
            if (await evasivedrive(chase.turn)) {
              animation.stop();
              return await footChaseSequence();
            }
          } else if (c == Key.f) {
            // Get list of enemies that are in the nearest vehicle
            List<Creature> enemiesInNearestVehicle = encounter
                .where((e) => e.car == nearestVehicle && e.alive)
                .toList();
            clearMessageArea();
            mvaddstrc(
              9,
              1,
              lightGray,
              "You open fire on the ${nearestVehicle.fullName()} from ",
            );
            switch (nearestVehicleDistance) {
              case <= 0:
                addstrc(lightGreen, "point blank range");
              case <= 5:
                addstrc(lightBlue, "${5 * nearestVehicleDistance} feet away");
              case <= 10:
                addstrc(yellow, "${5 * nearestVehicleDistance} feet away");
              default:
                addstrc(red, "${5 * nearestVehicleDistance} feet away");
            }
            addstrc(lightGray, "!");
            await acknowledge(title: 'Pursuit report');
            await combatRound(enemiesInNearestVehicle);
            for (Vehicle v in chaseSequence!.enemycar) {
              chaseSequence!.enemyCarDistance[v] =
                  (chaseSequence!.enemyCarDistance[v] ?? 70) - lcsRandom(5);
            }
            chase.turn--;
            if (await enemyCarUpdate()) {
              animation.stop();
              return await footChaseSequence();
            }
          }
          timePassed = true;
        }
      } else {
        CarChaseReaction? reaction;
        if (c == Key.d) {
          reaction = CarChaseReaction.dodge;
          chase.turn++;
        } else if (c == Key.f) {
          reaction = CarChaseReaction.slowDown;
        } else if (c == Key.g && canDeliberatelyHit) {
          reaction = CarChaseReaction.speedUp;
          chase.turn++;
        }
        if (reaction != null) {
          if (await obstacledrive(obstacle, reaction)) {
            if (partyalive > 0) {
              animation.stop();
              return await footChaseSequence();
            }
          }
          timePassed = true;
        }
      }

      if (timePassed) {
        await creatureadvance();
        if (await drivingupdate()) {
          if (partyalive > 0) {
            animation.stop();
            return await footChaseSequence();
          }
        } else {
          //SET UP NEXT OBSTACLE
          if (oneIn(3)) {
            obstacle = CarChaseObstacles.values.random;
          } else {
            obstacle = null;
          }
        }
      }

      //HAVE YOU LOST ALL OF THEM?
      //THEN LEAVE
      int baddiecount = encounter
          .where((e) => e.car != null && e.isEnemy && e.alive)
          .length;
      if (partyalive > 0 && baddiecount == 0) {
        await encounterMessage("It looks like you've lost them!");
        for (BodyPart w in operationParticipants(
          siegeSite: chaseSequence?.site,
        ).expand((p) => p.body.parts)) {
          w.bleeding = 0;
        }
        mode = GameMode.base;
        animation.stop();
        return ChaseOutcome.escape;
      }
    }
  } finally {
    animation.stop();
    await animationTask;
  }
}

/// Publishes precisely the current original car reader, after its text/actions.
void _publishCarPursuit() {
  if (partyalive > 0) {
    for (var index = 0; index < squad.length; index++) {
      final person = squad[index];
      final key = '${index + 1}';
      if (!console.actions.any((action) => action.key == key)) {
        move(index + 2, 0);
        console.addAction(key, '$key - Check ${person.name}');
      }
      console.annotateAction(key, 'Check ${person.name}');
      console.annotateActionEntity(key, type: 'person', id: '${person.id}');
    }
    move(9, 1);
    console.addAction(
      '0',
      'Show squad status',
      enabled: activeSquadMemberIndex != -1,
    );
  }
  String line(int row) => console.buffer[row]
      .map((cell) => cell.glyph)
      .join()
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  console.screen = 'pursuit';
  console.pursuit = PursuitContext(
    title: 'Car pursuit',
    threatSummary: 'Pursuing vehicles: ${chaseSequence!.enemycar.length}',
    location: chaseSequence!.location.getName(),
    note: chaseSequence!.canpullover
        ? 'Pulling over ends the pursuit in police custody. Bailing out abandons your cars.'
        : 'Surrender is unavailable in this pursuit. Bailing out abandons your cars.',
    people: console.journalPeople,
    statusLines: [
      for (var row = 9; row < 12; row++)
        if (line(row).isNotEmpty) line(row),
    ],
    encounterLines: [
      for (var row = 14; row < 22; row++)
        if (line(row).isNotEmpty) line(row),
    ],
    actions: console.actions,
  );
}

enum ChaseOutcome {
  victory,
  escape,
  capture,
  death;

  bool get won => this == ChaseOutcome.victory || this == ChaseOutcome.escape;
}

Future<ChaseOutcome> footChaseSequence({
  bool showStandardText = true,
  Site? autoPromoteFromSitePool,
  String? introduction,
}) async {
  //NOTE: THIS FUNCTION RETURNS TRUE IF ANYBODY ESCAPES
  await reloadparty(false);

  //NUKE ALL CARS
  chaseSequence!.enemycar.clear();

  //BAIL IF NO CHASERS
  int chasenum = encounter.length;
  for (Creature e in encounter) {
    e.carId = -1;
  }
  if (chasenum == 0) return ChaseOutcome.victory;

  if (mode == GameMode.carChase) {
    chaseSequence!.chaseAnimation.stop();
    showStandardText = false;
  }

  mode = GameMode.footChase;

  if (showStandardText) {
    erase();
    if (introduction != null) {
      mvaddstrc(0, 0, white, introduction);
    } else {
      mvaddstrc(0, 0, white, "As you exit the site, you notice that you are ");
      move(1, 0);
      addstr("being followed by Conservative swine!");
    }
    await acknowledge(title: 'Pursuit report');
  }

  bool ranAway = false;

  while (true) {
    if (autoPromoteFromSitePool != null) {
      autopromote(autoPromoteFromSitePool);
    }

    erase();
    mvaddstrc(0, 0, lightGray, chaseSequence!.location.getName());

    //PRINT PARTY
    if (partyalive == 0) activeSquadMemberIndex = -1;
    printParty();
    if (partyalive == 0) {
      //DESTROY ALL CARS BROUGHT ALONG WITH PARTY
      vehiclePool.removeWhere((v) => chaseSequence!.friendcar.contains(v));

      for (Creature p in List.of(squad)) {
        p.die();
        p.location = null;
        p.squad = null;
      }

      addOptionText(9, 1, 'C', 'C - Reflect on your Conservative ineptitude.');
    } else {
      printChaseOptions();
    }

    //PRINT ENEMIES
    printChaseEncounter();

    // Describe this exact awaited pursuit again after an invalid key, a squad
    // status view, or a nested equipment/order reader. Never reuse its actions.
    if (partyalive > 0) {
      for (var index = 0; index < squad.length; index++) {
        final person = squad[index];
        final key = '${index + 1}';
        if (!console.actions.any((action) => action.key == key)) {
          move(index + 2, 0);
          console.addAction(key, '$key - Check ${person.name}');
        }
        console.annotateAction(key, 'Check ${person.name}');
        console.annotateActionEntity(
          key,
          type: 'person',
          id: person.id.toString(),
        );
      }
      move(9, 1);
      console.addAction(
        '0',
        'Show squad status',
        enabled: activeSquadMemberIndex != -1,
      );
    }
    console.annotateAction('d', 'Try to lose them');
    console.annotateAction('f', 'Fight');
    console.annotateAction('e', 'Equipment');
    console.annotateAction('o', 'Squad orders');
    console.annotateAction('g', 'Give up and surrender');
    console.screen = 'pursuit';
    console.pursuit = PursuitContext(
      threatSummary: 'Pursuers: ${encounter.where((e) => e.isEnemy && e.alive).length}',
      location: chaseSequence!.location.getName(),
      note: chaseSequence!.canpullover
          ? 'Giving up ends the pursuit in police custody.'
          : 'Giving up is unavailable in this pursuit.',
      people: console.journalPeople,
      encounterLines: [
        for (
          var row = 12;
          row < min(console.height, 12 + encounter.length);
          row++
        )
          console.buffer[row]
              .map((cell) => cell.glyph)
              .join()
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim(),
      ],
      actions: console.actions,
    );

    int c = await getKey();

    if (partyalive == 0 && c == Key.c) {
      if (!await checkForDefeat()) {
        mode = GameMode.base;
        return ChaseOutcome.death;
      }
    }

    if (partyalive > 0) {
      await handleChaseSquadOptions(c);
      if (c == Key.g && chaseSequence!.canpullover) {
        await chaseGiveUp();
        mode = GameMode.base;
        return ChaseOutcome.capture;
      }
      if (c == Key.d || c == Key.f) {
        if (encounter.any((e) => e.type.lawEnforcement)) {
          sitestory?.drama.add(Drama.footChase);
          criminalizeAll(squad, Crime.resistingArrest);
          if (encounter.any((e) => e.type.id == CreatureTypeIds.deathSquad)) {
            // Death squads: Resist arrest and now they just want to kill you
            chaseSequence!.canpullover = false;
          }
        }
        if (c == Key.d) {
          ranAway = true;
          await evasiverun();
          await enemyattack(encounter);
          await creatureadvance();
        } else if (c == Key.f) {
          await combatRound(encounter);
        }
        await creatureadvance();
      }

      if (c == Key.e) await equip(activeSquad!.loot);

      //HAVE YOU LOST ALL OF THEM?
      //THEN LEAVE
      int baddiecount = encounter.where((e) => e.isEnemy && e.alive).length;
      if (partyalive > 0 && baddiecount == 0) {
        if (showStandardText) {
          setColor(white);
          clearMessageArea();
          if (!ranAway) {
            mvaddstr(9, 1, "A Liberal outcome!");
          } else {
            mvaddstr(9, 1, "It looks like you've lost them!");
          }
          await acknowledge(title: 'Pursuit report');
        }
        for (BodyPart w in operationParticipants(
          siegeSite: chaseSequence?.site,
        ).expand((p) => p.body.parts)) {
          w.bleeding = 0;
        }
        mode = GameMode.base;
        if (ranAway) {
          return ChaseOutcome.escape;
        } else {
          return ChaseOutcome.victory;
        }
      }
    }
  }
}

const drivingRandomness = 13;
Future<bool> evasivedrive(int turn) async {
  List<int> yourRolls = [], theirRolls = [];
  List<Vehicle> theirRollsCar = [];
  List<Creature> theirRollsDriver = [];
  int yourworst = 10000;
  for (Creature p in squad) {
    if (p.alive && p.isDriver) {
      Vehicle v = p.car!;
      yourRolls.add(driveskill(p, v) + lcsRandom(drivingRandomness + turn));
      p.train(Skill.driving, lcsRandom(50));
      if (yourworst > yourRolls.last) yourworst = yourRolls.last;
    }
  }
  if (yourRolls.isEmpty) yourRolls.add(0); //error -- and for this you get a 0

  List<Creature> toRemove = [];
  for (Creature e in encounter) {
    if (e.carId != -1 && e.isEnemy && e.alive && e.isDriver) {
      theirRolls
          .add(driveskill(e, e.car!) + lcsRandom(drivingRandomness + turn));
      theirRollsCar.add(e.car!);
      theirRollsDriver.add(e);
    } else if (e.carId == -1) {
      toRemove.add(e);
    }
  }
  encounter.removeWhere((e) => toRemove.contains(e));

  await encounterMessage([
    "You pick up speed on a long straightaway.",
    "You swerve around the next corner.",
    "You screech through an empty lot to the next street.",
    "You thread the needle between two obstacles.",
    "You downshift abruptly, engine growling as you corner hard.",
    "You take a sharp turn, tires squealing.",
    "You dodge a pothole and keep the pedal down.",
    "You take a shortcut through a parking lot.",
    "The tires grip just enough as you drift through a sharp turn.",
    "You take a risky shortcut through an alley.",
    "You soar into a downhill curve, barely keeping control.",
    "You take a sharp turn, the car fishtailing.",
    "You clip a stack of barrels, sending them rolling behind you.",
  ].random);

  for (int i = 0; i < theirRolls.length; i++) {
    Vehicle enemyCar = theirRollsCar[i];
    // Update enemy car distance
    int delta = yourworst - theirRolls[i] + turn;
    int enemyCarDistance = chaseSequence!.enemyCarDistance[enemyCar] ?? 70;
    if (enemyCarDistance < 15) delta ~/= 2;
    if (enemyCarDistance > 30) delta *= 2;
    enemyCarDistance += delta;
    if (enemyCarDistance <= 0) enemyCarDistance = 0;
    debugPrint(
        "${enemyCar.fullName()} distance: ${chaseSequence!.enemyCarDistance[enemyCar]} => $enemyCarDistance");
    chaseSequence!.enemyCarDistance[enemyCar] = enemyCarDistance;
  }
  return enemyCarUpdate();
}

Future<bool> enemyCarUpdate() async {
  void abandonCars() {
    vehiclePool
        .removeWhere((v) => chaseSequence?.friendcar.contains(v) ?? false);
    chaseSequence?.friendcar.clear();
    for (Creature p in squad) {
      p.carId = null;
    }
  }

  for (Vehicle enemyCar in chaseSequence!.enemycar.toList()) {
    Creature? enemyCarDriver =
        encounter.firstWhereOrNull((c) => c.car == enemyCar && c.isDriver);
    if (enemyCarDriver == null) {
      await crashenemycar(enemyCar);
      continue;
    }
    int enemyCarDistance = chaseSequence!.enemyCarDistance[enemyCar] ?? 70;
    if (enemyCarDistance >= 60 + chaseSequence!.turn ||
        enemyCarDriver.blood < enemyCarDriver.maxBlood ~/ 2) {
      // You lost them
      await backOffEnemyCar(enemyCar);
    } else if (enemyCarDistance <= 0) {
      // They're right up on your ass
      clearMessageArea();
      mvaddstrc(
        9,
        1,
        red,
        [
          "${enemyCar.fullName()} pulls alongside you!",
          "${enemyCar.fullName()} rolls up and rides your tailgate!",
          "${enemyCar.fullName()} is riding your bumper!",
          "${enemyCar.fullName()} rams into you from behind!",
          "${enemyCar.fullName()} draws dangerously close!",
          "${enemyCar.fullName()} moves to cut you off!",
          "${enemyCar.fullName()} tries to force you off the road!",
          "${enemyCar.fullName()} tries to box you in!",
        ].random,
      );
      await acknowledge(title: 'Pursuit report');

      Creature yourDriver = squad.where((p) => p.isDriver).toList().random;
      Vehicle yourCar = yourDriver.car!;
      int attack =
          driveskill(enemyCarDriver, enemyCar) + lcsRandom(drivingRandomness);
      int defense = driveskill(yourDriver, yourCar) +
          lcsRandom(drivingRandomness + chaseSequence!.turn);
      if (!yourDriver.alive) {
        mvaddstrc(10, 1, red,
            "${yourCar.fullName().toUpperCase()}'S DRIVER IS DEAD!");
        chaseSequence!.crash();
        await acknowledge(title: 'Pursuit report');
        await crashfriendlycar(yourCar);
        return true;
      } else if (attack > defense + 15) {
        mvaddstrc(
            10,
            1,
            red,
            [
              "${yourDriver.name} completely loses control!!!",
              "Your ${yourCar.fullName()} spins out of control!!!",
              "Your ${yourCar.fullName()} fishtails wildly!!!",
              "${yourDriver.name} loses control of the ${yourCar.fullName()}!!!",
            ].random);
        await acknowledge(title: 'Pursuit report');
        chaseSequence!.crash();
        if (oneIn(3)) {
          await crashfriendlycar(yourCar);
        } else {
          clearMessageArea();
          mvaddstrc(
              9,
              1,
              yellow,
              [
                "${yourCar.fullName()} slides sideways into a building.",
                "${yourCar.fullName()} spins out and stops.",
                "${yourCar.fullName()} skids to a stop.",
                "${yourCar.fullName()} comes to a rest facing backwards.",
                "${yourCar.fullName()} crashes into some greenery.",
              ].random);
          await acknowledge(title: 'Pursuit report');
          mvaddstrc(
              10, 1, lightGray, "The squad will have to face them on foot!");
          await acknowledge(title: 'Pursuit report');
        }
        abandonCars();
        return true;
      } else if (attack > defense + 5) {
        mvaddstrc(
            10,
            1,
            red,
            [
              "${enemyCarDriver.name} runs ${yourDriver.name} off the road!",
              "${enemyCarDriver.name} sends ${yourDriver.name} into a spin!",
            ].random);
        chaseSequence!.crash();
        await acknowledge(title: 'Pursuit report');
        mvaddstrc(
            11, 1, lightGray, "The squad will have to face them on foot!");
        await acknowledge(title: 'Pursuit report');
        abandonCars();
        return true;
      } else if (defense > attack + 5) {
        mvaddstrc(
            10,
            1,
            lightGreen,
            [
              "${yourDriver.name} runs ${enemyCar.fullName()} off the road!",
              "${yourDriver.name} hits ${enemyCar.fullName()} hard!",
              "${yourDriver.name} sends ${enemyCar.fullName()} out of control!",
              "${enemyCar.fullName()} spins out of control!",
            ].random);
        await acknowledge(title: 'Pursuit report');
        await crashenemycar(enemyCar);
      } else {
        mvaddstrc(
            10,
            1,
            yellow,
            [
              "Metal grinds on metal, but ${yourDriver.name} holds the line!",
              "${yourDriver.name} and ${enemyCar.fullName()} trade paint!",
              "${yourDriver.name} swerves, but recovers!",
              "${yourDriver.name} and ${enemyCar.fullName()} race inches apart!",
            ].random);
        await acknowledge(title: 'Pursuit report');
      }
    }
  }
  return false;
}

Future<void> evasiverun() async {
  Map<Creature, int> yourspeed = {for (Creature p in squad) p: 0};
  int yourworst = 10000, yourbest = 0, theirbest = 0, theirworst = 10000;
  for (Creature p in squad) {
    if (p.alive) {
      if (p.hasWheelchair) {
        yourspeed[p] = 0;
      } else {
        yourspeed[p] = p.attributeRoll(Attribute.agility);
      }
      if (yourworst > yourspeed[p]!) yourworst = yourspeed[p]!;
      if (yourbest < yourspeed[p]!) yourbest = yourspeed[p]!;
    }
  }

  if (yourworst > 14) {
    yourworst += lcsRandom(5);

    clearMessageArea();
    setColor(white);
    move(9, 1);

    switch (lcsRandom(yourworst ~/ 5)) {
      case 1:
        addstr("You run as fast as you can!");
      case 2:
        addstr("You climb a fence in record time!");
      case 3:
        addstr("You scale a small building and leap between rooftops!");
      default:
        addstr("You suddenly dart into an alley!");
    }

    await acknowledge(title: 'Pursuit report');
  }

  for (int i = encounter.length - 1; i >= 0; i--) {
    Creature e = encounter[i];
    int chaser = e.attributeRoll(Attribute.agility);

    if (theirbest < chaser) theirbest = chaser;
    if (theirworst > chaser) theirworst = chaser;

    if (e.type.tank && !oneIn(10)) {
      clearMessageArea();
      mvaddstrc(9, 1, yellow, e.name);
      switch (lcsRandom(4)) {
        case 0:
          addstr(" plows through a brick wall like it was nothing!");
        case 1:
          addstr(" charges down an alley, smashing both side walls out!");
        case 2:
          addstr(" smashes straight through traffic, demolishing cars!");
        case 3:
          addstr(" destroys everything in its path to keep up!");
      }

      await acknowledge(title: 'Pursuit report');
    } else if (chaser < yourworst) {
      clearMessageArea();
      mvaddstrc(9, 1, lightBlue, e.name);
      if (e.type.tank) {
        addstr(" tips into a pool. The tank is trapped!");
      } else {
        addstr(" can't keep up!");
      }
      encounter.removeAt(i);
      printChaseEncounter();
      await acknowledge(title: 'Pursuit report');
    } else {
      clearMessageArea();
      mvaddstrc(9, 1, yellow, e.name);
      addstr(" is still on your tail!");
      await acknowledge(title: 'Pursuit report');
    }
  }

  //This last loop can be used to have fast people in
  //your squad escape one by one just as the enemy
  //falls behind one by one
  int othersleft = 0;
  for (int i = squad.length - 1; i >= 0; i--) {
    Creature p = squad[i];
    if (encounter.isEmpty) break;
    if (p.alive) {
      if (yourspeed[p]! > theirbest) {
        if (i == 0 && othersleft == 0) break;
        clearMessageArea();
        mvaddstrc(9, 1, lightBlue, p.name);
        addstr(" breaks away!");
        await acknowledge(title: 'Pursuit report');

        //Unload hauled hostage or body when they get back to the safehouse
        if (p.prisoner != null) {
          //If this is an LCS member or corpse being hauled
          if (pool.contains(p.prisoner)) {
            //Take them out of the squad
            p.prisoner!.squad = null;
            //Set base and current location to squad's safehouse
            p.prisoner!.location = p.base;
            p.prisoner!.base = p.base;
          } else //A kidnapped conservative
          {
            //Convert them into a prisoner
            await kidnaptransfer(p.prisoner!);
          }
          p.prisoner = null;
        }

        p.squad = null;
        p.location = p.base;

        printParty();
      } else if (yourspeed[p]! < theirbest - 10) {
        clearMessageArea();
        String message = p.name;
        switch (encounter[0].type.id) {
          case CreatureTypeIds.policeChief:
          case CreatureTypeIds.cop:
            message += " is seized, ";
            if (laws[Law.policeReform]! >= DeepAlignment.liberal) {
              message += "pushed to the ground, and handcuffed!";
            } else {
              if (p.blood <= 10) {
                message += "thrown to the ground, and TAZED TO DEATH!";
              } else {
                message += "thrown to the ground, and tazed repeatedly!";
              }
              p.blood -= 10;
            }
          case CreatureTypeIds.deathSquad:
            message +=
                " is seized, thrown to the ground, and SHOT IN THE HEAD!";
            p.blood = 0;
          case CreatureTypeIds.tank:
            message += " is CRUSHED beneath the tank's treads!";
            p.blood = 0;
          default:
            message += " is seized, ";
            if (p.blood <= 60) {
              message += "slammed against the ground, and BEATEN TO DEATH!";
            } else {
              message += "slammed against the ground, and brutally beaten!";
            }
            p.blood -= 60;
        }
        if (p.blood <= 0) {
          p.die();
        }

        await captureCreature(p);
        // Death squads don't mess around, and don't fall behind when executing your people
        // Tanks don't stop either.
        if (encounter[0].type.id != CreatureTypeIds.deathSquad &&
            encounter[0].type.tank) {
          encounter.removeAt(0);
        }

        printParty();
        printChaseEncounter();
        mvaddstrc(9, 1, lightBlue, message);

        await acknowledge(title: 'Pursuit report');
      } else {
        othersleft++;
      }
    }
  }
}

int driveskill(Creature cr, Vehicle v) {
  int driveskill = cr.skill(Skill.driving) + v.type.driveBonus * 2;
  healthmodroll(driveskill, cr);
  if (driveskill < 0) driveskill = 0;
  driveskill = (driveskill * cr.blood / cr.maxBlood * 2).round();
  return driveskill;
}

Future<bool> drivingupdate() async {
  await creatureadvance();
  //CHECK TO SEE WHICH CARS ARE BEING DRIVEN
  for (int i = chaseSequence!.friendcar.length - 1; i >= 0; i--) {
    Vehicle v = chaseSequence!.friendcar[i];
    Iterable<Creature> potentialDriver =
        squad.where((p) => p.carId == v.id && !p.body.fullParalysis && p.alive);
    Creature? driver = potentialDriver.firstWhereOrNull((p) => p.isDriver);

    if (potentialDriver.isNotEmpty && driver == null) {
      //MAKE BEST DRIVING PASSENGER INTO A DRIVER
      int maxp =
          potentialDriver.fold(0, (value, p) => max(value, driveskill(p, v)));
      Iterable<Creature> goodp =
          potentialDriver.where((p) => driveskill(p, v) == maxp);

      if (goodp.isNotEmpty) {
        squad.where((p) => p.carId == v.id).forEach((p) => p.isDriver = false);
        Creature p = goodp.random;
        p.isDriver = true;
        driver = p;

        clearMessageArea();
        mvaddstrc(9, 1, yellow, "${p.name} takes over the wheel.");
        printParty();
        await acknowledge(title: 'Pursuit report');
      }
    }
    if (driver == null) {
      await crashfriendlycar(v);
      return true;
    }
  }

  for (int i = chaseSequence!.enemycar.length - 1; i >= 0; i--) {
    Vehicle v = chaseSequence!.enemycar[i];
    Creature? driver = encounter
        .firstWhereOrNull((p) => p.carId == v.id && p.isDriver && p.canWalk);
    // Enemies don't take over the wheel when driver incapacitated
    if (driver == null) {
      await crashenemycar(v);
    }
  }

  return enemyCarUpdate();
}

void makeChasers(SiteType? sitetype, int sitecrime) {
  encounter.clear();

  if (sitecrime <= 0) return;

  int n;

  String cartype; //Temporary (transitionally) solution. -XML
  int pnum;

  chaseSequence!.canpullover = false;
  // 50% of CCS harassing your teams once they reach the
  // "attacks" stage (but not for activities, which are
  // law enforcement response specific)
  if (ccsState.index < CCSStrength.defeated.index &&
      ccsState.index >= CCSStrength.attacks.index &&
      oneIn(2) &&
      sitetype != null &&
      activeSite?.city.sites.any((s) => s.controller == SiteController.ccs) ==
          true) {
    cartype = "PICKUP";
    pnum = lcsRandom(sitecrime ~/ 5 + 1) + 1;
    if (pnum > 12) pnum = 12;
    for (n = 0; n < pnum; n++) {
      encounter.add(Creature.fromId(CreatureTypeIds.ccsVigilante));
    }
  } else {
    String creatureType;
    switch (sitetype) {
      case SiteType.armyBase:
        cartype = "HMMWV";
        pnum = lcsRandom(sitecrime ~/ 5 + 1) + 3;
        creatureType = CreatureTypeIds.soldier;
      case SiteType.whiteHouse:
        cartype = "AGENTCAR";
        pnum = lcsRandom(sitecrime ~/ 5 + 1) + 1;
        if (pnum > 6) pnum = 6;
        creatureType = CreatureTypeIds.secretService;
      case SiteType.intelligenceHQ:
        cartype = "AGENTCAR";
        pnum = lcsRandom(sitecrime ~/ 5 + 1) + 1;
        if (pnum > 6) pnum = 6;
        creatureType = CreatureTypeIds.agent;
      case SiteType.corporateHQ:
      case SiteType.ceoHouse:
        if (oneIn(2)) {
          cartype = "SUV";
        } else {
          cartype = "JEEP";
        }
        pnum = lcsRandom(sitecrime ~/ 5 + 1) + 1;
        if (pnum > 6) pnum = 6;
        creatureType = CreatureTypeIds.merc;
      case SiteType.amRadioStation:
      case SiteType.cableNewsStation:
        cartype = "PICKUP";
        pnum = lcsRandom(sitecrime ~/ 3 + 1) + 1;
        if (pnum > 18) pnum = 18;
        creatureType = CreatureTypeIds.angryRuralMob;
      case SiteType.drugHouse:
        cartype = ["STATIONWAGON", "SPORTSCAR"].random;
        pnum = lcsRandom(sitecrime ~/ 3 + 1) + 1;
        if (pnum > 18) pnum = 18;
        creatureType = CreatureTypeIds.gangMember;
      default:
        chaseSequence!.canpullover = true;
        cartype = "POLICECAR";
        pnum = lcsRandom(sitecrime ~/ 5 + 1) + 1;
        if (pnum > 6) pnum = 6;
        if (deathSquadsActive) {
          creatureType = CreatureTypeIds.deathSquad;
          // Uncomment this if we want death squads to not a viable surrender
          // target; classically, you can surrender to a death squad member
          // on the first round of combat.
          //chaseSequence!.canpullover = false;
        } else if (laws[Law.policeReform]! <= DeepAlignment.conservative) {
          creatureType = CreatureTypeIds.gangUnit;
        } else {
          creatureType = CreatureTypeIds.cop;
        }
    }
    if (pnum > ENCMAX) pnum = ENCMAX;
    for (n = 0; n < pnum; n++) {
      encounter.add(Creature.fromId(creatureType));
    }
  }

  for (n = 0; n < pnum; n++) {
    conservatize(encounter[n]);
  }

  //ASSIGN CARS TO CREATURES
  int carnum;
  if (pnum <= 2) {
    carnum = 1;
  } else if (pnum <= 3) {
    carnum = lcsRandom(2) + 1;
  } else if (pnum <= 5) {
    carnum = lcsRandom(2) + 2;
  } else if (pnum <= 7) {
    carnum = lcsRandom(2) + 3;
  } else {
    carnum = 4;
  }

  for (int c = 0; c < carnum; c++) {
    //If car type is unknown, due to change in xml file, the game will crash here. -XML
    Vehicle v = Vehicle(vehicleTypes[cartype]!.idName);
    chaseSequence!.enemycar.add(v);
    chaseSequence!.enemyCarDistance[v] = 6 * (c + 1) + lcsRandom(8 * (c + 1));

    for (n = 0; n < pnum; n++) {
      if (encounter[n].carId == null) {
        encounter[n].carId = v.id;
        encounter[n].isDriver = true;
        break;
      }
    }
  }

  List<int> load = [for (int i = 0; i < chaseSequence!.enemycar.length; i++) 0];

  for (Creature e in encounter.where((e) => e.carId == null)) {
    int v;
    int goal = 4;
    if (cartype == "POLICECAR") goal = 2;
    while (!load.any((l) => l < goal)) {
      goal++;
    }
    do {
      v = lcsRandom(chaseSequence!.enemycar.length);
      e.carId = chaseSequence!.enemycar[v].id;
      e.isDriver = false;
    } while (load[v] >= goal);
    load[v]++;
  }

  for (Creature e in encounter) {
    e.noticedParty = true;
  }
}

enum CarChaseReaction {
  dodge,
  slowDown,
  speedUp,
}

Future<bool> obstacledrive(
    CarChaseObstacles obstacle, CarChaseReaction reaction) async {
  Future<void> slowDown(String safemove, String reckless) async {
    clearMessageArea();
    mvaddstrc(9, 1, yellow, "You slow down and $safemove.");
    chaseSequence!.turn--;
    chaseSequence!.enemyCarDistance
        .updateAll((key, value) => max(value - 5, 0));
    await acknowledge(title: 'Pursuit report');
  }

  switch (obstacle) {
    case CarChaseObstacles.crossTraffic:
      if (reaction == CarChaseReaction.dodge ||
          reaction == CarChaseReaction.speedUp) {
        return dodgedrive(style: CarChaseReaction.speedUp);
      } else if (reaction == CarChaseReaction.slowDown) {
        await slowDown("turn the corner", "take it hot");
      }
    case CarChaseObstacles.truckPullsOut:
      if (reaction == CarChaseReaction.dodge ||
          reaction == CarChaseReaction.speedUp) {
        return dodgedrive();
      } else if (reaction == CarChaseReaction.slowDown) {
        await slowDown("carefully evade the truck",
            "are on your ${noProfanity ? '[bumper]' : 'ass'}");
      }
    case CarChaseObstacles.fruitStand:
      if (reaction == CarChaseReaction.dodge) {
        return dodgedrive();
      } else if (reaction == CarChaseReaction.slowDown) {
        await slowDown("navigate the market", "crash through it");
      } else if (reaction == CarChaseReaction.speedUp) {
        clearMessageArea();
        mvaddstrc(9, 1, yellow, "Fruit smashes all over the windshield!");
        await acknowledge(title: 'Pursuit report');
        if (oneIn(5)) {
          mvaddstrc(10, 1, red, "A fruit seller is squashed!");
          await acknowledge(title: 'Pursuit report');
          criminalizeAll(squad.where((p) => p.isDriver), Crime.murder);
          addDramaToSiteStory(Drama.killedSomebody);
        }
      }
    case CarChaseObstacles.child:
      if (reaction == CarChaseReaction.dodge) {
        return dodgedrive();
      } else if (reaction == CarChaseReaction.slowDown) {
        await slowDown("avoid the kid", "start shooting anyway!!");
      }
  }
  return false;
}

Future<bool> dodgedrive(
    {CarChaseReaction style = CarChaseReaction.dodge}) async {
  clearMessageArea();
  if (style == CarChaseReaction.dodge) {
    mvaddstrc(9, 1, yellow, "You swerve to avoid the obstacle!");
  } else if (style == CarChaseReaction.speedUp) {
    mvaddstrc(9, 1, yellow, "You ride the accelerator!");
  }
  await acknowledge(title: 'Pursuit report');

  for (Vehicle v in chaseSequence!.friendcar.toList()) {
    Creature? driver =
        squad.firstWhereOrNull((s) => s.carId == v.id && s.isDriver);
    if (driver?.skillCheck(Skill.driving, Difficulty.easy) != true) {
      await crashfriendlycar(v);
      sitestory?.drama.add(Drama.carCrash);
      return true;
    }
  }
  for (Vehicle v in chaseSequence!.enemycar.toList()) {
    Creature? driver =
        encounter.firstWhereOrNull((e) => e.carId == v.id && e.isDriver);
    if (driver?.skillCheck(Skill.driving, Difficulty.easy) != true) {
      await crashenemycar(v);
      sitestory?.drama.add(Drama.carCrash);
    } else {
      chaseSequence!.enemyCarDistance.updateAll((key, value) => value + 3);
    }
  }
  return false;
}

Future<void> crashfriendlycar(Vehicle v) async {
  sitestory?.drama.add(Drama.carCrash);
  const List<String> crashesFlavorText = [
    " slams into a building!",
    " skids out and crashes!",
    " hits another car and flips over!"
  ];
  const List<String> diesFlavorText = [
    " is crushed inside the car.",
    "'s lifeless body smashes through the windshield.",
    " is thrown from the car and killed instantly.",
  ];

  chaseSequence!.crash();

  //CRASH CAR
  clearMessageArea();
  mvaddstrc(9, 1, purple, "Your ");
  addstr(v.fullName());
  addstr(crashesFlavorText.random);
  printParty();

  await acknowledge(title: 'Pursuit report');

  for (int i = squad.length - 1; i >= 0; i--) {
    Creature p = squad[i];
    if (p.carId == v.id) {
      // Inflict injuries on Liberals
      for (BodyPart w in p.body.parts) {
        // If limb is intact
        if (!w.missing) {
          // Inflict injuries
          if (oneIn(3)) {
            w.torn = true;
            w.bleeding += 1;
            p.blood -= 1 + lcsRandom(15);
          }
          if (oneIn(3)) {
            w.cut = true;
            w.bleeding += 1;
            p.blood -= 1 + lcsRandom(15);
          }
          if (oneIn(2)) {
            w.bruised = true;
            p.blood -= 1 + lcsRandom(5);
          }
        }
      }

      // Kill off hostages
      if (p.prisoner != null) {
        // Instant death
        if (p.prisoner!.alive) {
          clearMessageArea();
          mvaddstrc(9, 1, red, p.prisoner!.name);
          addstr(diesFlavorText.random);
          printParty();
          await acknowledge(title: 'Pursuit report');
        }

        // Record death if living Liberal is hauled
        p.prisoner!.location = null;
        p.prisoner!.die();
        p.prisoner = null;
      }

      // Handle squad member death
      if (p.blood <= 0) {
        // Inform the player
        clearMessageArea();
        mvaddstrc(9, 1, red, p.name);
        int range = 3;
        if (p.body.fullParalysis) range -= 1;
        switch (lcsRandom(range)) {
          case 0:
            addstr(" slumps in ");
            addstr(p.gender.hisHer);
            addstr(" seat, out cold, and dies.");
          case 1:
            addstr(" is crushed by the impact.");
          case 2:
            addstr(" struggles free of the car, then collapses lifelessly.");
        }
        printParty();

        await acknowledge(title: 'Pursuit report');

        p.die();

        // Remove dead Liberal from squad
        p.squadId = null;
        squad.remove(p);
      } else {
        // Inform the player of character survival
        clearMessageArea();
        mvaddstrc(9, 1, yellow, p.name);
        int roll = lcsRandom(3);
        if (p.body.fullParalysis) roll = 1;
        switch (roll) {
          case 0:
            addstr(" grips the ");
            if (p.equippedWeapon != null) {
              addstr(p.weapon.getName(sidearm: true));
            } else {
              addstr("car frame");
            }
            addstr(" and struggles to ");
            addstr(p.gender.hisHer);
            if (p.hasWheelchair) {
              addstr(" wheelchair.");
            } else {
              addstr(" feet.");
            }
          case 1:
            addstr(" gasps in pain, but lives, for now.");
          case 2:
            addstr(" crawls free of the car, shivering with pain.");
            p.dropWeapon();
        }
        printParty();
        await acknowledge(title: 'Pursuit report');
      }
    }
  }

  //GET RID OF CARS
  vehiclePool.removeWhere((v) => chaseSequence?.friendcar.contains(v) ?? false);
  chaseSequence?.friendcar.clear();
  for (Creature p in squad) {
    p.carId = null;
  }
}

Future<void> crashenemycar(Vehicle v) async {
  sitestory?.drama.add(Drama.carCrash);
  int victimsum = 0;
  for (int i = encounter.length - 1; i >= 0; i--) {
    Creature p = encounter[i];
    if (p.carId == v.id) {
      victimsum++;
      encounter.removeAt(i);
    }
  }

  //CRASH CAR
  clearMessageArea();
  mvaddstrc(9, 1, lightBlue, "The ");
  addstr(v.fullName());
  switch (lcsRandom(3)) {
    case 0:
      addstr(" slams into a building.");
    case 1:
      addstr(" spins out and crashes.");
      move(10, 1);
      if (victimsum > 1) {
        addstr("Everyone inside is peeled off against the pavement.");
      } else if (victimsum == 1) {
        addstr("The person inside is squashed into a cube.");
      }
    case 2:
      addstr(" hits a parked car and flips over.");
  }
  chaseSequence?.enemycar.remove(v);
  chaseSequence?.enemyCarDistance.remove(v);
  printChaseEncounter();
  await acknowledge(title: 'Pursuit report');
}

Future<void> chaseGiveUp() async {
  final participants = operationParticipants(siegeSite: chaseSequence?.site);
  Site? ps =
      findSiteInSameCity(chaseSequence!.location.city, SiteType.policeStation);
  vehiclePool.removeWhere((v) => chaseSequence!.friendcar.contains(v));
  chaseSequence!.friendcar.clear();
  int hostagefreed = 0;
  for (Creature p in squad.toList()) {
    p.squad = null;
    p.carId = null;
    p.location = ps;
    p.dropWeaponAndAmmo();
    p.activity.type = ActivityType.none;
    if (p.prisoner != null) {
      if (p.prisoner!.align != Alignment.liberal) hostagefreed++;
      await freehostage(p, FreeHostageMessage.none);
    }
  }
  for (BodyPart w in participants.expand((p) => p.body.parts)) {
    w.bleeding = 0;
  }
  clearMessageArea();
  setColor(purple);
  move(9, 1);
  if (mode != GameMode.carChase) {
    addstr("You stop and are arrested.");
  } else {
    addstr("You pull over and are arrested.");
  }
  chaseSequence!.crash();
  if (hostagefreed > 0) {
    mvaddstr(10, 1, "Your hostage");
    if (hostagefreed > 1) {
      addstr("s are free.");
    } else {
      addstr(" is free.");
    }
  }
  await acknowledge(title: 'Pursuit report');
}

Future<ChaseOutcome> soloChaseSequence(Creature cr, int pursuitStrength,
    {Vehicle? v}) async {
  chaseSequence = ChaseSequence(cr.site?.district ??
      cr.location ??
      cr.base?.district ??
      cr.base?.city ??
      (Site(SiteType.armsDealer, cities.first, cities.first.districts.first)
        ..name = "In The Bugfield"));
  makeChasers(chaseSequence?.site?.type, pursuitStrength);
  Squad? oldSquad = cr.squad;
  Squad sq = Squad();
  squads.add(sq);
  sq.members.add(cr);
  cr.squadId = sq.id;
  cr.carId = v?.id;
  if (cr.carId != null) cr.isDriver = true;

  Squad? oact = activeSquad;
  int ops = activeSquadMemberIndex;
  activeSquad = sq;
  activeSquadMemberIndex = 0;
  ChaseOutcome ret;
  if (v == null) {
    ret = await footChaseSequence(
      introduction: '${cr.name} is being pursued on foot.',
    );
  } else {
    ret = await carChaseSequence(
      introduction: '${cr.name} is being pursued by car.',
    );
  }
  squads.remove(sq);

  activeSquadMemberIndex = ops;

  if (ret.won) {
    cr.squadId = oldSquad?.id;
  } else {
    cr.squadId = null;
    oldSquad?.members.remove(cr);
  }
  activeSquad = oact;
  return ret;
}

Future<void> backOffEnemyCar(Vehicle v) async {
  Creature driver = encounter.firstWhere((e) => e.carId == v.id && e.isDriver);
  clearMessageArea();
  setColor(lightBlue);
  if (driver.blood < driver.maxBlood ~/ 2) {
    chaseSequence!.enemyCarDistance[v] = 80;
    mvaddstrc(
      9,
      1,
      lightBlue,
      [
        "${v.fullName()} pulls over as ${driver.name} bleeds out.",
        "${v.fullName()} bails on the chase as the driver bleeds.",
        "${v.fullName()} rapidly pulls back.",
        "${v.fullName()} retreats from the pursuit.",
        "${v.fullName()} stops by the side of the road.",
        "${v.fullName()} bows out as ${driver.name} gives up.",
        "${v.fullName()} backs away completely.",
        "${v.fullName()} struggles due to ${driver.name}'s injuries.",
      ].random,
    );
  } else {
    mvaddstrc(
      9,
      1,
      lightBlue,
      [
        "${v.fullName()} couldn't keep up.",
        "${v.fullName()} gives up as ${driver.name} loses confidence.",
        "${v.fullName()} trails behind and is lost.",
        "${v.fullName()} vanishes far behind you.",
        "${v.fullName()} is left behind.",
        "${v.fullName()} can't keep up and disappears from view.",
        "${v.fullName()} bows out as ${driver.name} gives up.",
        "${v.fullName()} backs away completely.",
        "${v.fullName()} struggles to maintain speed and falls away.",
      ].random,
    );
  }
  await acknowledge(title: 'Pursuit report');
  encounter.removeWhere((e) => e.carId == v.id);
  chaseSequence!.enemycar.remove(v);
  chaseSequence!.enemyCarDistance.remove(v);
}
