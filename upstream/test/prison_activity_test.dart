import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide escape;
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/difficulty.dart';
import 'package:lcs_new_age/creature/prison_activity.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature prisoner;
  late Site prisonSite;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  void load() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    prisoner = game.pool.first;
    prisonSite = game.sites.firstWhere((s) => s.type == SiteType.prison);
    prisoner
      ..location = prisonSite
      ..align = Alignment.liberal
      ..sentence = 12
      ..deathPenalty = false
      ..sleeperAgent = false
      ..prisonActivity = null;
    prisoner.rawAttributes.updateAll((key, value) => 30);
    prisoner.rawSkillXP.updateAll((key, value) => 0);
    game.laws[Law.prisons] = DeepAlignment.moderate;
    reseedRNG(seed: 20261024);
  }

  setUp(load);

  void nextMonth() =>
      game.gameState.date = DateTime(game.date.year, game.date.month + 1, 1);
  int evidenceCount() => game.sites
      .expand((site) => site.loot)
      .where((item) => item.typeName == LootTypeIds.prisonFiles)
      .fold(0, (sum, item) => sum + item.stackSize);
  void succeedingWritingRoll() {
    prisoner.rawSkill[Skill.writing] = 20;
    final seed = Iterable.generate(10000).firstWhere((seed) {
      reseedRNG(seed: seed);
      return prisoner.skillCheck(Skill.writing, Difficulty.average);
    });
    reseedRNG(seed: seed);
  }

  test(
    'old saves default to no project; unknown orders and counters are safe',
    () {
      expect(
        game.pool.every((person) => person.prisonActivity == null),
        isTrue,
      );
      final state = PrisonActivity.fromJson({
        'order': 'future-order',
        'contacts': 999,
        'documentProgress': -5,
      });
      expect(state.order, PrisonOrder.keepHeadDown);
      expect(state.contacts, maxPrisonContacts);
      expect(state.documentProgress, 0);
      prisoner.prisonActivity = state
        ..order = PrisonOrder.documentConditions
        ..documentProgress = 2
        ..pendingDocument = true
        ..lastResolvedMonth = 24322
        ..lastReport = 'Retained monthly report';
      final original = jsonEncode(game.gameState.toJson());
      game.gameState = game.GameState.fromJson(jsonDecode(original));
      expect(jsonEncode(game.gameState.toJson()), original);
      final restored = game.pool
          .firstWhere((person) => person.id == prisoner.id)
          .prisonActivity!;
      expect(restored.order, PrisonOrder.documentConditions);
      expect(restored.pendingDocument, isTrue);
      expect(restored.lastReport, 'Retained monthly report');
    },
  );

  test('only sentenced living Liberal prisoners can receive orders', () {
    expect(prisonOrderUnavailableReason(prisoner), isNull);
    final activity = prisoner.activity;
    prisoner.location = game.sites.firstWhere(
      (s) => s.type == SiteType.policeStation,
    );
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.location = game.sites.firstWhere(
      (s) => s.type == SiteType.courthouse,
    );
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.location = prisonSite;
    prisoner.sleeperAgent = true;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.sleeperAgent = false;
    prisoner.sentence = 0;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.sentence = 1;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.sentence = 12;
    prisoner.deathPenalty = true;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.deathPenalty = false;
    prisoner.alive = false;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    prisoner.alive = true;
    prisoner.align = Alignment.conservative;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isFalse);
    expect(prisoner.prisonActivity, isNull);
    expect(identical(prisoner.activity, activity), isTrue);
  });

  test('study gives real XP once per month without replacing daily orders', () {
    prisoner.activity = Activity(ActivityType.trouble);
    final daily = jsonEncode(prisoner.activity);
    prisoner.rawSkill[Skill.law] = 0;
    expect(setPrisonOrder(prisoner, PrisonOrder.studyLaw), isTrue);
    expect(resolvePrisonActivity(prisoner), contains('+30 XP'));
    expect(prisoner.skillXP(Skill.law), 30);
    expect(resolvePrisonActivity(prisoner), isNull);
    setPrisonOrder(prisoner, PrisonOrder.studyWriting);
    expect(resolvePrisonActivity(prisoner), isNull);
    expect(prisoner.skillXP(Skill.writing), 0);
    nextMonth();
    expect(resolvePrisonActivity(prisoner), contains('Writing'));
    expect(prisoner.skillXP(Skill.writing), 30);
    expect(jsonEncode(prisoner.activity), daily);
  });

  test('law changes pause projects without erasing progress', () {
    setPrisonOrder(prisoner, PrisonOrder.studyLaw);
    game.laws[Law.prisons] = DeepAlignment.archConservative;
    expect(resolvePrisonActivity(prisoner), contains('study materials'));
    expect(prisoner.skillXP(Skill.law), 0);
    expect(setPrisonOrder(prisoner, PrisonOrder.studyWriting), isFalse);
    nextMonth();
    game.laws[Law.prisons] = DeepAlignment.eliteLiberal;
    expect(resolvePrisonActivity(prisoner), contains('+50 XP'));
    expect(setPrisonOrder(prisoner, PrisonOrder.documentConditions), isFalse);
    expect(prisoner.prisonActivity!.order, PrisonOrder.studyLaw);
  });

  test(
    'default prison processing preserves historical RNG and outcomes',
    () async {
      final seed = Iterable.generate(10000).firstWhere((seed) {
        reseedRNG(seed: seed);
        return !oneIn(5);
      });
      reseedRNG(seed: seed);
      await playChoices(() => prison(prisoner), (_, _, _) => 'Enter');
      final expectedRolls = List.generate(8, (_) => lcsRandom(100000));
      final expectedSentence = prisoner.sentence;
      expect(prisoner.prisonActivity, isNull);
      load();
      prisoner.prisonActivity = PrisonActivity();
      reseedRNG(seed: seed);
      await playChoices(() => prison(prisoner), (_, _, _) => 'Enter');
      expect(prisoner.sentence, expectedSentence);
      expect(List.generate(8, (_) => lcsRandom(100000)), expectedRolls);
      expect(prisoner.prisonActivity!.lastResolvedMonth, isNull);
    },
  );

  test('monthly handler studies before countdown, pauses final month, releases cleanly', () async {
    prisoner.sentence = 2;
    prisoner.rawSkill[Skill.law] = 0;
    setPrisonOrder(prisoner, PrisonOrder.studyLaw);
    final seed = Iterable.generate(10000).firstWhere((seed) {
      reseedRNG(seed: seed);
      return !oneIn(5);
    });
    reseedRNG(seed: seed);
    await playChoices(() => prison(prisoner), (_, _, _) => 'Enter');
    expect(prisoner.skillXP(Skill.law), 30);
    expect(prisoner.sentence, 1);
    nextMonth();
    await playChoices(() => prison(prisoner), (_, _, _) => 'Enter');
    expect(prisoner.sentence, 0);
    expect(prisoner.site?.type, isNot(SiteType.prison));
    expect(prisoner.skillXP(Skill.law), 30);
    expect(prisoner.prisonActivity!.order, PrisonOrder.keepHeadDown);
    expect(resolvePrisonActivity(prisoner), isNull);
  });

  test(
    'contact network is bounded and shared only with prisoners at that site',
    () {
      prisoner.rawSkill[Skill.persuasion] = 20;
      setPrisonOrder(prisoner, PrisonOrder.buildContacts);
      prisoner.prisonActivity!.contacts = 5;
      final seed = Iterable.generate(10000).firstWhere((seed) {
        reseedRNG(seed: seed);
        return prisoner.skillCheck(Skill.persuasion, Difficulty.average);
      });
      reseedRNG(seed: seed);
      expect(resolvePrisonActivity(prisoner), contains('(6/6)'));
      expect(prisonContacts(prisoner), 6);
      nextMonth();
      expect(resolvePrisonActivity(prisoner), contains('maintained'));
      expect(prisoner.prisonActivity!.contacts, 6);
      final other = game.pool.firstWhere((person) => person != prisoner);
      other
        ..location = prisonSite
        ..sentence = 12
        ..align = Alignment.liberal
        ..prisonActivity = (PrisonActivity()..contacts = 3);
      prisoner.prisonActivity!.contacts = 0;
      expect(prisonContacts(prisoner), 3);
      other.sleeperAgent = true;
      expect(prisonContacts(prisoner), 0);
    },
  );

  test(
    'three successful months create one publishable dossier per sentence',
    () {
      setPrisonOrder(prisoner, PrisonOrder.documentConditions);
      final before = evidenceCount();
      for (int month = 0; month < 3; month++) {
        succeedingWritingRoll();
        expect(resolvePrisonActivity(prisoner), isNotNull);
        expect(resolvePrisonActivity(prisoner), isNull);
        nextMonth();
      }
      expect(evidenceCount(), before + 1);
      expect(prisoner.prisonActivity!.documentCompleted, isTrue);
      expect(prisoner.prisonActivity!.pendingDocument, isFalse);
      expect(resolvePrisonActivity(prisoner), contains('already completed'));
      expect(evidenceCount(), before + 1);
      setPrisonOrder(prisoner, PrisonOrder.keepHeadDown);
      nextMonth();
      setPrisonOrder(prisoner, PrisonOrder.documentConditions);
      resolvePrisonActivity(prisoner);
      expect(evidenceCount(), before + 1);
    },
  );

  test(
    'undeliverable dossier survives release and save, then delivers once',
    () {
      final safehouse = game.sites.firstWhere(
        (site) =>
            site.cityId == prisonSite.cityId &&
            site.controller == SiteController.lcs,
      );
      for (final site in game.sites.where(
        (site) => site.cityId == prisonSite.cityId,
      )) {
        site.controller = SiteController.unaligned;
      }
      setPrisonOrder(prisoner, PrisonOrder.documentConditions);
      prisoner.prisonActivity!.documentProgress = 2;
      succeedingWritingRoll();
      final before = evidenceCount();
      expect(resolvePrisonActivity(prisoner), contains('awaits'));
      expect(evidenceCount(), before);
      expect(prisoner.prisonActivity!.pendingDocument, isTrue);
      endPrisonActivity(prisoner);
      prisoner.location = safehouse;
      expect(prisoner.prisonActivity!.pendingDocument, isTrue);
      final id = prisoner.id;
      game.gameState = game.GameState.fromJson(
        jsonDecode(jsonEncode(game.gameState)),
      );
      prisoner = game.pool.firstWhere((person) => person.id == id);
      game.sites.firstWhere((site) => site.id == safehouse.id).controller =
          SiteController.lcs;
      expect(deliverPendingPrisonDocuments(prisoner), contains('reached'));
      expect(deliverPendingPrisonDocuments(prisoner), isNull);
      expect(evidenceCount(), before + 1);
    },
  );

  test('escape and new imprisonment reset episode progress, retain pending evidence', () {
    prisoner.prisonActivity = PrisonActivity()
      ..order = PrisonOrder.documentConditions
      ..contacts = 4
      ..documentProgress = 2
      ..pendingDocument = true
      ..documentCompleted = true;
    escape(prisoner, false);
    expect(prisoner.prisonActivity!.order, PrisonOrder.keepHeadDown);
    expect(prisoner.prisonActivity!.contacts, 0);
    expect(prisoner.prisonActivity!.documentProgress, 0);
    expect(prisoner.prisonActivity!.pendingDocument, isTrue);
    prisoner.sentence = 12;
    imprison(prisoner);
    expect(prisoner.site?.type, SiteType.prison);
    expect(prisoner.prisonActivity!.documentCompleted, isFalse);
    expect(prisoner.prisonActivity!.pendingDocument, isTrue);
  });
}
