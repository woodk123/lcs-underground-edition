import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/difficulty.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/arrest.dart';
import 'package:lcs_new_age/daily/activities/fundraising.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/justice/trial.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// Only provides player input; every effect is resolved by the retained engine.
/// Unexpected extra decisions fail instead of silently choosing a default.
Future<List<String>> playChoices(
  Future<void> Function() operation,
  String Function(String frame, List<ConsoleAction> actions, int prompt)
  choose, {
  Duration timeout = const Duration(seconds: 10),
  int promptLimit = 80,
}) async {
  final console = engine.console;
  final frames = <String>[];
  final failure = Completer<void>();
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    final frame = console.buffer
        .map((row) => row.map((cell) => cell.glyph).join().trimRight())
        .join('\n');
    frames.add(frame);
    try {
      if (frames.length > promptLimit) {
        throw StateError('Exceeded $promptLimit prompts. Last frame: $frame');
      }
      final key = choose(frame, List.of(console.actions), frames.length - 1);
      if (!console.sendInput(key)) throw StateError('Input $key rejected.');
    } catch (error, stack) {
      if (!failure.isCompleted) failure.completeError(error, stack);
    }
  }

  console.revision.addListener(respond);
  try {
    await Future.any([operation(), failure.future]).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Engine decision stalled: ${frames.lastOrNull}',
      ),
    );
  } finally {
    console.revision.removeListener(respond);
  }
  expect(console.awaitingInput, isFalse);
  return frames;
}

void roundTripLiveCampaign() {
  final original = jsonEncode(game.gameState.toJson());
  game.gameState = game.GameState.fromJson(
    jsonDecode(original) as Map<String, dynamic>,
  );
  expect(jsonEncode(game.gameState.toJson()), original);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    final save = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
          as Map<String, dynamic>,
    );
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    reseedRNG(seed: 20261013);
    game.mode = GameMode.base;
    game.activeSite = game.squad.first.site;
  });

  for (final surrender in [true, false]) {
    test(
      'police-interrupted brownies do not pay after ${surrender ? 'capture' : 'escape'}',
      () async {
        final seller = game.squad.first;
        seller.activity = Activity(ActivityType.sellDrugs);
        seller.income = 0;
        seller.rawSkill[Skill.streetSmarts] = 0;
        seller.rawAttributes[Attribute.agility] = 30;
        game.laws[Law.drugs] = DeepAlignment.moderate;
        final seed = Iterable.generate(10000).firstWhere((seed) {
          reseedRNG(seed: seed);
          return oneIn(45) &&
              !seller.skillCheck(Skill.streetSmarts, Difficulty.average);
        });
        reseedRNG(seed: seed);
        final funds = game.ledger.funds;
        final earned = game.ledger.totalIncome;
        final businessXp = seller.rawSkillXP[Skill.business];
        await playChoices(() => doActivitySellBrownies([seller]), (
          frame,
          actions,
          prompt,
        ) {
          final choice = actions
              .where((a) => a.key == (surrender ? 'g' : 'd') && a.enabled)
              .firstOrNull;
          return choice?.key ?? 'Enter';
        });
        expect(seller.alive, isTrue);
        expect(seller.imprisoned, surrender);
        expect(seller.income, 0);
        expect(game.ledger.funds, funds);
        expect(game.ledger.totalIncome, earned);
        expect(seller.rawSkillXP[Skill.business], businessXp);
        roundTripLiveCampaign();
      },
    );
  }

  test('uninterrupted brownie work still pays and trains normally', () async {
    final seller = game.squad.first;
    seller.income = 0;
    game.laws[Law.drugs] = DeepAlignment.moderate;
    final seed = Iterable.generate(10000).firstWhere((seed) {
      reseedRNG(seed: seed);
      return !oneIn(45);
    });
    reseedRNG(seed: seed);
    final funds = game.ledger.funds;
    final xp = seller.rawSkillXP[Skill.business]!;
    await doActivitySellBrownies([seller]);
    expect(seller.income, greaterThan(0));
    expect(game.ledger.funds, funds + seller.income);
    expect(seller.rawSkillXP[Skill.business], xp + 5);
  });

  test(
    'ready recruit joins the real roster and retains the recruiter link',
    () async {
      final recruiter = game.pool.firstWhere(
        (person) => person.subordinatesLeft > 0,
      );
      final recruit = Creature.fromId(CreatureTypeIds.hippie);
      recruit.location = recruiter.location;
      final session = RecruitmentSession(recruit, recruiter);
      // A ready-candidate fixture exercises the actual join route; it does not
      // claim to have earned eagerness through earlier persuasion sessions.
      session.rawEagerness = 4;
      game.recruitmentSessions.add(session);
      final oldCount = game.pool.length;
      final oldStats = game.stats.recruits;
      final oldFunds = game.ledger.funds;
      final oldDate = game.date;
      final keys = ['c', 'Enter', 'Enter', 'a'];
      final frames = await playChoices(
        () async {
          expect(await completeRecruitMeeting(session, recruiter), isTrue);
        },
        (frame, actions, prompt) {
          if (prompt >= keys.length) {
            throw StateError('Unexpected recruit prompt.');
          }
          if (prompt == 0) {
            expect(
              actions.singleWhere((action) => action.key == 'c').enabled,
              isTrue,
            );
          }
          if (prompt == 3) {
            expect(
              actions.singleWhere((action) => action.key == 'a').label,
              contains('regular member'),
            );
          }
          return keys[prompt];
        },
      );
      expect(frames, hasLength(keys.length));
      expect(game.pool, hasLength(oldCount + 1));
      expect(
        game.pool.where((person) => person.id == recruit.id).single,
        same(recruit),
      );
      expect(recruit.boss, same(recruiter));
      expect(recruit.align, Alignment.liberal);
      expect(recruit.sleeperAgent, isFalse);
      expect(recruit.base, recruiter.base);
      expect(recruit.location, recruiter.base);
      expect(game.recruitmentSessions, isNot(contains(session)));
      expect(game.stats.recruits, oldStats + 1);
      expect(game.ledger.funds, oldFunds);
      expect(game.date, oldDate);
      roundTripLiveCampaign();
      final reloaded = game.pool.singleWhere(
        (person) => person.id == recruit.id,
      );
      expect(reloaded.boss?.id, recruiter.id);
      expect(reloaded.base?.id, recruiter.base?.id);
      expect(game.stats.recruits, oldStats + 1);
    },
  );

  test(
    'actual police pursuit accepts surrender and preserves custody on reload',
    () async {
      final liberal = game.squad.first;
      final oldSquad = liberal.squad!;
      final oldLoot = jsonEncode(
        oldSquad.loot.map((item) => item.toJson()).toList(),
      );
      final oldMemberIds = oldSquad.members.map((person) => person.id).toSet();
      final oldSquadIds = game.squads.map((squad) => squad.id).toSet();
      final oldDate = game.date;
      final oldFunds = game.ledger.funds;
      criminalize(liberal, Crime.theft);
      final wanted = Map.of(liberal.wantedForCrimes);
      final frames = await playChoices(
        () => attemptArrest(liberal, 'fundraising'),
        (frame, actions, prompt) {
          if (prompt == 2) {
            final surrender = actions.singleWhere(
              (action) => action.key == 'g',
            );
            expect(surrender.enabled, isTrue);
            expect(surrender.label, contains('Give up'));
            return surrender.key;
          }
          if (prompt > 3) throw StateError('Unexpected arrest prompt.');
          return 'Enter';
        },
      );
      expect(frames, hasLength(4));
      expect(frames.first, contains('accosted by police while fundraising'));
      expect(frames.last, contains('You stop and are arrested.'));
      expect(liberal.alive, isTrue);
      expect(liberal.site?.type, SiteType.policeStation);
      expect(liberal.imprisoned, isTrue);
      expect(liberal.squad, isNull);
      expect(liberal.equippedWeapon, isNull);
      expect(liberal.spareAmmo, isNull);
      expect(liberal.activity.type, ActivityType.none);
      expect(liberal.wantedForCrimes, wanted);
      expect(game.mode, GameMode.base);
      expect(game.activeSquad, oldSquad);
      expect(
        jsonEncode(oldSquad.loot.map((item) => item.toJson()).toList()),
        oldLoot,
      );
      expect(game.squads.map((squad) => squad.id).toSet(), oldSquadIds);
      expect(
        oldSquad.members.map((person) => person.id).toSet(),
        oldMemberIds..remove(liberal.id),
      );
      expect(game.ledger.funds, oldFunds);
      expect(game.date, oldDate);
      roundTripLiveCampaign();
      final reloaded = game.pool.singleWhere(
        (person) => person.id == liberal.id,
      );
      expect(reloaded.imprisoned, isTrue);
      expect(reloaded.squad, isNull);
      expect(reloaded.wantedForCrimes, wanted);
    },
  );

  test(
    'retained combat round resolves both sides and consumes real ammunition',
    () async {
      final liberal = game.squad.first;
      for (final other in List.of(game.squad).skip(1)) {
        other.squad = null;
      }
      final enemy = Creature.fromId(CreatureTypeIds.cop);
      enemy.align = Alignment.conservative;
      enemy.cantRunAway = true;
      liberal.giveWeaponAndAmmo('WEAPON_9MM_HANDGUN', 1);
      enemy.giveWeaponAndAmmo('WEAPON_9MM_HANDGUN', 1);
      game.encounter.add(enemy);
      game.mode = GameMode.footChase;
      game.siteAlarm = true;
      final oldDate = game.date;
      final liberalAmmo = liberal.weapon.ammo;
      final enemyAmmo = enemy.weapon.ammo;
      final liberalBlood = liberal.blood;
      final frames = await playChoices(
        () => combatRound(game.encounter),
        (frame, actions, prompt) => 'Enter',
      );
      expect(frames.length, greaterThanOrEqualTo(4));
      expect(liberal.justAttacked, isTrue);
      expect(enemy.justAttacked, isTrue);
      expect(liberal.weapon.ammo, lessThan(liberalAmmo));
      expect(enemy.weapon.ammo, lessThan(enemyAmmo));
      expect(liberal.blood, lessThan(liberalBlood));
      expect(game.siteCrime, greaterThan(0));
      expect(game.date, oldDate);
      expect(frames.any((frame) => frame.contains(liberal.name)), isTrue);
      expect(frames.any((frame) => frame.contains(enemy.name)), isTrue);
      final ammoAfter = liberal.weapon.ammo;
      final bloodAfter = liberal.blood;
      roundTripLiveCampaign();
      final reloaded = game.pool.singleWhere(
        (person) => person.id == liberal.id,
      );
      expect(reloaded.weapon.ammo, ammoAfter);
      expect(reloaded.blood, bloodAfter);
    },
  );

  test(
    'theft trial sentences a prisoner and real prison updates release them',
    () async {
      final liberal = game.squad.first;
      final oldDate = game.date;
      // Explicit two-count theft fixture; capture, trial, sentencing and every
      // prison update below use real rules rather than preselected outcomes.
      liberal.wantedForCrimes.updateAll((crime, count) => 0);
      criminalize(liberal, Crime.theft);
      criminalize(liberal, Crime.theft);
      await captureCreature(liberal);
      expect(liberal.site?.type, SiteType.policeStation);
      var pleadedGuilty = false;
      final trialFrames = await playChoices(() => trial(liberal), (
        frame,
        actions,
        prompt,
      ) {
        final pleas = actions.where(
          (action) =>
              action.key == 'c' && action.label.contains('Plead guilty'),
        );
        if (!pleadedGuilty && pleas.isNotEmpty) {
          expect(pleas.single.enabled, isTrue);
          pleadedGuilty = true;
          return pleas.single.key;
        }
        return 'Enter';
      });
      expect(pleadedGuilty, isTrue);
      expect(
        trialFrames.any((frame) => frame.contains('2 counts of theft')),
        isTrue,
      );
      expect(
        trialFrames.any((frame) => frame.contains('court accepts the plea')),
        isTrue,
      );
      expect(trialFrames.any((frame) => frame.contains('GUILTY!')), isTrue);
      expect(liberal.alive, isTrue);
      expect(liberal.sentence, inInclusiveRange(1, 8));
      expect(liberal.deathPenalty, isFalse);
      expect(liberal.site?.type, SiteType.prison);
      expect(liberal.isCriminal, isFalse);
      expect(liberal.heat, 0);
      expect(liberal.squad, isNull);
      final sentence = liberal.sentence;
      var updates = 0;
      final prisonFrames = <String>[];
      while (liberal.sentence > 0 && updates < 8) {
        final before = liberal.sentence;
        prisonFrames.addAll(
          await playChoices(
            () => prison(liberal),
            (frame, actions, prompt) => 'Enter',
          ),
        );
        updates++;
        expect(liberal.sentence, before - 1);
      }
      expect(updates, sentence);
      expect(liberal.sentence, 0);
      expect(liberal.alive, isTrue);
      expect(liberal.imprisoned, isFalse);
      expect(liberal.location, liberal.base);
      expect(
        prisonFrames.any(
          (frame) => frame.contains('has been released from prison'),
        ),
        isTrue,
      );
      // These are direct monthly subsystem calls, not elapsed calendar months.
      expect(game.date, oldDate);
      roundTripLiveCampaign();
      final reloaded = game.pool.singleWhere(
        (person) => person.id == liberal.id,
      );
      expect(reloaded.sentence, 0);
      expect(reloaded.imprisoned, isFalse);
      expect(reloaded.location, reloaded.base);
    },
  );
}
