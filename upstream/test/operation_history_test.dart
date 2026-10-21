import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_actions/common_actions.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/operation_record.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/operation_history.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

Object? withoutHistory(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys)
      if (key != 'operationHistory') key: withoutHistory(value[key]),
  },
  List() => value.map(withoutHistory).toList(),
  _ => value,
};

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
    game.activeSite = game.sites.firstWhere(
      (s) => s.type == SiteType.insuranceOffice,
    );
    for (final person in game.pool) {
      person.operationHistory.clear();
      person.wantedForCrimes.updateAll((_, _) => 0);
      person.heat = 0;
      person.juice = 0;
    }
    reseedRNG(seed: 20261018);
  });

  test(
    'old campaigns start empty; observation does not invent historical raids',
    () {
      expect(game.pool.every((p) => p.operationHistory.isEmpty), isTrue);
      final before = jsonEncode(game.gameState);
      reseedRNG(seed: 38123);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 38123);
      final capture = OperationHistoryCapture(game.activeSite!);
      capture.finish();
      expect(jsonEncode(game.gameState), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'source outcomes persist per actor without altering gameplay or RNG',
    () {
      final person = game.squad.first;
      final other = game.squad.last;
      final site = game.activeSite!;
      final originalName = site.getName(includeCity: true);
      final originalDate = game.date;
      final originalBlood = person.blood;
      final capture = OperationHistoryCapture(site);
      person.criminalize(Crime.theft);
      person.criminalize(Crime.breakingAndEntering);
      person.juice += 50;
      person.blood -= 5;
      (person.body as HumanoidBody).torso
        ..bruised = true
        ..relativeHealth = .8;
      person.train(Skill.security, 20);
      game.activeSquad!.loot.add(Loot(LootTypeIds.insuranceFraudEvidence));
      site.highSecurity += 12;
      game.politics.publicOpinion[View.healthcare] =
          game.politics.publicOpinion[View.healthcare]! + .25;
      final expected = withoutHistory(jsonDecode(jsonEncode(game.gameState)));
      reseedRNG(seed: 38123);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 38123);
      capture.finish();
      capture.finish(); // A repeated completion cannot duplicate an event.
      expect(withoutHistory(jsonDecode(jsonEncode(game.gameState))), expected);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      final record = person.operationHistory.single;
      expect(record.date, originalDate);
      expect(record.siteName, originalName);
      expect(record.newCharges, {Crime.theft: 1, Crime.breakingAndEntering: 1});
      expect(record.heatBefore, 0);
      expect(record.heatAfter, 0);
      expect(record.juiceChange, 50);
      // Juice can change maximum blood through attribute ranks. Preserve the
      // actual balance rather than assuming only injury changed it.
      expect(record.bloodChange, person.blood - originalBlood);
      expect(record.injuries, contains('Torso: bruised, 80% tissue health'));
      expect(record.trainingXp[Skill.security], greaterThan(0));
      expect(record.squadResults.join(' '), contains('Carried out:'));
      expect(record.squadResults.join(' '), contains('Heightened security:'));
      expect(record.opinionChanges, {View.healthcare: .25});
      expect(other.operationHistory.single.newCharges, isEmpty);
      expect(other.operationHistory.single.juiceChange, 0);
      final historical = jsonEncode(record);
      site.name = 'Renamed later';
      person.wantedForCrimes.updateAll((_, _) => 0);
      person.juice = 999;
      expect(jsonEncode(record), historical);
      final envelope = SaveFile(
        version: '1.5.6',
        saveData: game.gameState.toJson(),
        gameId: '${game.gameState.uniqueGameId}',
        lastPlayed: null,
      );
      final loaded = decodeSaveContents(
        encodeSaveContents(envelope),
      ).gameState!;
      final restored = loaded.lcs.pool.singleWhere((p) => p.id == person.id);
      expect(jsonEncode(restored.operationHistory.single), historical);
      expect(restored.wantedForCrimes.values.every((n) => n == 0), isTrue);
    },
  );

  test(
    'capture retains departed participants, distinguishes custody and lost loot',
    () {
      final people = game.squad.toList();
      final capture = OperationHistoryCapture(game.activeSite!);
      final prison = game.sites.firstWhere((s) => s.type == SiteType.prison);
      game.activeSquad!.loot.add(Loot(LootTypeIds.insuranceFraudEvidence));
      for (final person in people) {
        person.location = prison;
        person.squad = null;
      }
      capture.finish();
      for (final person in people) {
        expect(
          person.operationHistory.single.outcome,
          OperationOutcome.captured,
        );
        expect(person.operationHistory.single.squadResults, isEmpty);
      }
    },
  );

  test('severe damage reports zero tissue health without healing the limb', () {
    final person = game.squad.first;
    final capture = OperationHistoryCapture(game.activeSite!);
    final limb = (person.body as HumanoidBody).torso
      ..bruised = true
      ..relativeHealth = -.373611;
    capture.finish();
    expect(limb.relativeHealth, -.373611);
    expect(
      person.operationHistory.single.injuries,
      contains('Torso: bruised, 0% tissue health'),
    );
    expect(capture.returnReport, contains('0% tissue health'));
    expect(capture.returnReport, isNot(contains('-37%')));
  });

  test(
    'rescued crew receive history; bodies carried in are not new casualties',
    () {
      final person = game.squad.first;
      final carriedBody = game.squad.last..alive = false;
      person.prisoner = carriedBody;
      final captive =
          Creature.fromJson(
              jsonDecode(jsonEncode(person)) as Map<String, dynamic>,
            )
            ..id = 90000
            ..name = 'Prepared captive'
            ..squad = null;
      captive.location = game.sites.firstWhere(
        (s) => s.type == SiteType.prison,
      );
      game.pool.add(captive);
      final capture = OperationHistoryCapture(game.activeSite!);
      captive.location = person.base;
      capture.finish();
      expect(carriedBody.operationHistory, isEmpty);
      expect(
        captive.operationHistory.single.outcome,
        OperationOutcome.returned,
      );
      expect(
        person.operationHistory.single.squadResults.join(' '),
        contains('Rescued from custody: Prepared captive.'),
      );
      expect(
        person.operationHistory.single.participants,
        isNot(contains(carriedBody.name)),
      );
    },
  );

  test('only the newest fifty significant operations are retained', () {
    final person = game.squad.first;
    for (var i = 0; i < operationHistoryLimit + 2; i++) {
      final capture = OperationHistoryCapture(game.activeSite!);
      person.juice++;
      capture.finish();
      game.gameState.date = game.date.add(const Duration(days: 1));
    }
    expect(person.operationHistory, hasLength(operationHistoryLimit));
    expect(
      person.operationHistory.first.date,
      game.date.subtract(const Duration(days: operationHistoryLimit)),
    );
  });

  for (final alarm in [false, true]) {
    test(
      'completed source operation records only alarm-committed crimes ($alarm)',
      () async {
        final person = game.squad.first;
        game.sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)
          ..loc = game.activeSite;
        var prepared = false;
        // Declared exit geometry and a pending offence exercise the real return,
        // cleanup and alarm-dependent commit path. No random result is replaced.
        await playChoices(() => siteMode(game.activeSite!), (_, _, _) {
          if (engine.console.screen == 'tactical' && !prepared) {
            prepared = true;
            currentTile.exit = true;
            game.siteAlarm = alarm;
            game.encounter.clear();
            addPotentialCrime([person], Crime.theft);
            juiceparty(5, 200);
            return 's';
          }
          return 'Enter';
        });
        expect(prepared, isTrue);
        final record = person.operationHistory.single;
        expect(record.outcome, OperationOutcome.returned);
        // The founder also receives the source's recruiter trickle-up rewards.
        expect(record.juiceChange, person.juice);
        expect(record.juiceChange, greaterThanOrEqualTo(5));
        expect(record.newCharges, alarm ? {Crime.theft: 1} : isEmpty);
        expect(game.gameState.potentialCrimes, isEmpty);
      },
    );
  }

  test('an interrupted source reader cannot commit an operation', () async {
    final interrupted = StateError('test reader interruption');
    void interrupt() {
      scheduleMicrotask(() {
        final pending = engine.console.nextKeyEvent;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(interrupted);
        }
      });
    }

    engine.console.revision.addListener(interrupt);
    try {
      await expectLater(siteMode(game.activeSite!), throwsA(same(interrupted)));
    } finally {
      engine.console.revision.removeListener(interrupt);
    }
    expect(game.pool.every((p) => p.operationHistory.isEmpty), isTrue);
  });
}
