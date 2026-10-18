import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/blind_time_log.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/monthly/sleeper_update.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Map<View, int> _power() => {for (final view in View.values) view: 0};

Future<List<String>> _reports(Future<void> Function() run) async {
  final reports = <String>[];
  void acknowledge() {
    if (!engine.console.awaitingInput || engine.console.lastKey != null) return;
    expect(engine.console.eventTitle, 'Sleeper report');
    expect(engine.console.eventMessage, isNotEmpty);
    reports.add(engine.console.eventMessage!.replaceAll(RegExp(r'\s+'), ' '));
    engine.console.sendInput('Enter');
  }

  engine.console.revision.addListener(acknowledge);
  try {
    await run().timeout(const Duration(seconds: 5));
  } finally {
    engine.console.revision.removeListener(acknowledge);
  }
  return reports;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature sleeper;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    clearBlindLog();
    sleeper = game.pool.last;
    sleeper
      ..name = 'Monthly Agent'
      ..sleeperAgent = true
      ..squad = null
      ..activity = Activity(ActivityType.sleeperEmbezzle)
      ..infiltration = .8
      ..hidingDaysLeft = 0
      ..vacationDaysLeft = 0;
    // Resolve the existing source identity check before deterministic operation
    // draws; it may lazily construct the president in this old save fixture.
    game.uniqueCreatures.president;
  });

  test(
    'embezzlement awaits one report with earnings and exposure together',
    () async {
      sleeper.typeId = CreatureTypeIds.corporateManager;
      final seed = List.generate(
        200,
        (i) => i,
      ).firstWhere((seed) => Random(seed).nextInt(100) > 72);
      reseedRNG(seed: seed);
      lcsRandom(100);
      final expectedNext = nextRngSeed;
      reseedRNG(seed: seed);
      final funds = game.ledger.funds;
      final monthly = game.ledger.income[Income.embezzlement] ?? 0;
      var completed = false;
      final flow = sleeperEmbezzle(
        sleeper,
        _power(),
      ).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.eventTitle, 'Sleeper report');
      final message = engine.console.eventMessage!;
      expect(message, contains('has embezzled \$3000'));
      expect(message, contains('noticed funds are going missing'));
      expect(message, contains('60% infiltration remains'));
      expect(game.ledger.funds, funds + 3000);
      expect(game.ledger.income[Income.embezzlement], monthly + 3000);
      expect(sleeper.infiltration, closeTo(.6, .000001));
      engine.console.sendInput('Enter');
      await flow;
      expect(completed, isTrue);
      expect(engine.console.awaitingInput, isFalse);
      expect(nextRngSeed, expectedNext);
    },
  );

  test(
    'successful embezzlement preserves original payout and random draws',
    () async {
      sleeper.typeId = CreatureTypeIds.corporateManager;
      final seed = List.generate(
        200,
        (i) => i,
      ).firstWhere((seed) => Random(seed).nextInt(100) <= 72);
      reseedRNG(seed: seed);
      lcsRandom(100);
      final expectedNext = nextRngSeed;
      reseedRNG(seed: seed);
      final funds = game.ledger.funds;
      final reports = await _reports(() => sleeperEmbezzle(sleeper, _power()));
      expect(reports, hasLength(1));
      expect(reports.single, contains('has embezzled \$4000'));
      expect(reports.single, isNot(contains('noticed')));
      expect(game.ledger.funds, funds + 4000);
      expect(sleeper.infiltration, .8);
      expect(nextRngSeed, expectedNext);
    },
  );

  test(
    'noticed theft reports actual delivery and exposure once without a blank pause',
    () async {
      final worksite = game.sites.firstWhere(
        (s) => s.type == SiteType.policeStation,
      );
      final camp = game.sites.firstWhere(
        (s) => s.type == SiteType.homelessEncampment && s.city == worksite.city,
      );
      sleeper
        ..workLocation = worksite
        ..activity = Activity(ActivityType.sleeperSteal);
      camp.loot.clear();
      final snapshot = jsonEncode(game.gameState.toJson());
      final personId = sleeper.id;
      final seed = List.generate(
        200,
        (i) => i,
      ).firstWhere((seed) => Random(seed).nextInt(100) > 76);
      reseedRNG(seed: seed);
      lcsRandom(100);
      final expectedInfiltration = .8 - .2 - (lcsRandom(10) * .01 - .02);
      var count = lcsRandom(10) + 1;
      final expectedLoot = <String>[];
      var delivered = 0;
      while (count-- > 0) {
        final item = lootItemForSite(worksite.type);
        if (item != null) {
          delivered += item.stackSize;
          expectedLoot.add(jsonEncode(item.toJson()));
        }
      }
      final expectedNext = nextRngSeed;
      game.gameState = game.GameState.fromJson(jsonDecode(snapshot));
      sleeper = game.pool.singleWhere((p) => p.id == personId);
      final restoredCamp = game.sites.singleWhere((s) => s.id == camp.id);
      reseedRNG(seed: seed);

      final reports = await _reports(() => sleeperSteal(sleeper, _power()));
      expect(reports, hasLength(1));
      expect(reports.single, contains('noticed things are going missing'));
      expect(reports.single, contains('Dead drop:'));
      expect(reports.single, contains(restoredCamp.name));
      expect(reports.single, contains('Move equipment between bases'));
      expect(
        reports.single,
        contains(delivered == 0 ? 'no equipment' : 'delivered $delivered'),
      );
      expect(sleeper.infiltration, closeTo(expectedInfiltration, .000001));
      expect(
        restoredCamp.loot.map((item) => jsonEncode(item.toJson())),
        expectedLoot,
      );
      expect(nextRngSeed, expectedNext);
    },
  );

  test(
    'legacy theft without a worksite reports a no-op without spending RNG',
    () async {
      sleeper
        ..workLocation = null
        ..activity = Activity(ActivityType.sleeperSteal);
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 79151);
      final expectedNext = nextRngSeed;
      reseedRNG(seed: 79151);
      final reports = await _reports(() => sleeperEffect(sleeper, _power()));
      expect(reports, hasLength(1));
      expect(reports.single, contains('no workplace equipment source'));
      expect(reports.single, contains('another standing order in Network'));
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(nextRngSeed, expectedNext);
    },
  );

  test(
    'Lay Low reports its real capped monthly gain and keeps its order',
    () async {
      sleeper
        ..activity = Activity.none()
        ..infiltration = .99;
      reseedRNG(seed: 10651);
      lcsRandom(5);
      final expectedNext = nextRngSeed;
      reseedRNG(seed: 10651);
      final reports = await _reports(() => sleeperEffect(sleeper, _power()));
      expect(reports, hasLength(1));
      expect(reports.single, contains('99% to 100%'));
      expect(reports.single, contains('standing order until you change it'));
      expect(sleeper.infiltration, 1);
      expect(sleeper.activity.type, ActivityType.none);
      expect(nextRngSeed, expectedNext);
    },
  );

  test(
    'source individual and bulk theft choices reject a missing worksite',
    () async {
      sleeper
        ..workLocation = null
        ..activity = Activity.none();
      final individual = activateSleeper(sleeper);
      await Future<void>.delayed(Duration.zero);
      engine.console.sendInput('b');
      await Future<void>.delayed(Duration.zero);
      final task = engine.console.actions.singleWhere(
        (a) =>
            a.entityType == 'sleeper-activity' && a.entityId == 'sleeperSteal',
      );
      expect(task.enabled, isFalse);
      expect(task.label, contains('no workplace'));
      engine.console.sendInput(task.key);
      await Future<void>.delayed(Duration.zero);
      expect(sleeper.activity.type, ActivityType.none);
      engine.console.sendInput('Escape');
      await individual;

      final bulk = activateSleepersBulk();
      await Future<void>.delayed(Duration.zero);
      engine.console.sendInput('5');
      await Future<void>.delayed(Duration.zero);
      final row = engine.console.actions.singleWhere(
        (a) => a.entityType == 'person' && a.entityId == sleeper.id.toString(),
      );
      expect(row.enabled, isFalse);
      expect(row.intentLabel, contains('No workplace equipment source'));
      engine.console.sendInput(row.key);
      await Future<void>.delayed(Duration.zero);
      expect(sleeper.activity.type, ActivityType.none);
      engine.console.sendInput('Escape');
      await bulk;
    },
  );

  test(
    'City-level journalist has no document source even after passing the snooping gate',
    () async {
      sleeper
        ..typeId = CreatureTypeIds.journalist
        ..workLocation = null
        ..activity = Activity(ActivityType.sleeperSpy)
        ..infiltration = 1;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 758329);
      lcsRandom(100);
      lcsRandom(3);
      final expectedNext = nextRngSeed;
      reseedRNG(seed: 758329);
      expect(sleeperHasDocumentSource(sleeper), isFalse);
      await sleeperSpy(sleeper, _power()).timeout(const Duration(seconds: 1));
      expect(engine.console.awaitingInput, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(nextRngSeed, expectedNext);

      sleeper.workLocation = game.sites.firstWhere(
        (s) => s.type == SiteType.policeStation,
      );
      expect(
        sleeperHasDocumentSource(sleeper),
        isFalse,
        reason:
            'A generic profession cannot use the police profession leak branch.',
      );
      sleeper.workLocation = game.sites.firstWhere(
        (s) => s.type == SiteType.corporateHQ,
      );
      expect(
        sleeperHasDocumentSource(sleeper),
        isTrue,
        reason: 'Corporate HQ has the generic workplace leak branch.',
      );
      sleeper
        ..typeId = CreatureTypeIds.cop
        ..workLocation = null;
      expect(
        sleeperHasDocumentSource(sleeper),
        isTrue,
        reason: 'The police profession has its own branch even without a Site.',
      );
    },
  );

  test(
    'blind monthly Lay Low and embezzlement log results without a reader',
    () async {
      game.cantSeeReason = CantSeeReason.hospital;
      sleeper
        ..activity = Activity.none()
        ..infiltration = .4;
      reseedRNG(seed: 10651);
      final gain = .01 * lcsRandom(5) + .01;
      final expectedRestNext = nextRngSeed;
      reseedRNG(seed: 10651);

      await sleeperEffect(
        sleeper,
        _power(),
      ).timeout(const Duration(seconds: 1));
      expect(sleeper.infiltration, closeTo(.4 + gain, .000001));
      expect(nextRngSeed, expectedRestNext);
      expect(engine.console.awaitingInput, isFalse);
      expect(engine.console.eventMessage, isNull);
      engine.erase();
      displayBlindLog();
      expect(
        engine.console.currentReportText(),
        contains('laid low this month'),
      );

      clearBlindLog();
      sleeper
        ..typeId = CreatureTypeIds.corporateManager
        ..activity = Activity(ActivityType.sleeperEmbezzle)
        ..infiltration = .8;
      final seed = List.generate(
        200,
        (i) => i,
      ).firstWhere((seed) => Random(seed).nextInt(100) > 72);
      reseedRNG(seed: seed);
      lcsRandom(100);
      final expectedEmbezzleNext = nextRngSeed;
      reseedRNG(seed: seed);
      final funds = game.ledger.funds;

      await sleeperEffect(
        sleeper,
        _power(),
      ).timeout(const Duration(seconds: 1));
      expect(game.ledger.funds, funds + 3000);
      expect(sleeper.infiltration, closeTo(.6, .000001));
      expect(nextRngSeed, expectedEmbezzleNext);
      expect(engine.console.awaitingInput, isFalse);
      expect(engine.console.eventMessage, isNull);
      engine.erase();
      displayBlindLog();
      final report = engine.console.currentReportText();
      expect(report, contains('has embezzled \$3000'));
      expect(report, contains('noticed funds are going missing'));
    },
  );

  test('blind theft failures log without input or a random draw', () async {
    game.cantSeeReason = CantSeeReason.hiding;
    sleeper
      ..workLocation = null
      ..activity = Activity(ActivityType.sleeperSteal);
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 587319);
    final expectedNext = nextRngSeed;
    reseedRNG(seed: 587319);
    await sleeperEffect(sleeper, _power()).timeout(const Duration(seconds: 1));
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(nextRngSeed, expectedNext);
    expect(engine.console.awaitingInput, isFalse);
    engine.erase();
    displayBlindLog();
    expect(
      engine.console.currentReportText().replaceAll(RegExp(r'\s+'), ' '),
      contains('no workplace equipment source'),
    );

    clearBlindLog();
    final worksite = game.sites.firstWhere(
      (s) => s.type == SiteType.policeStation,
    );
    sleeper.workLocation = worksite;
    for (final site in worksite.city.sites) {
      if (site.type == SiteType.homelessEncampment) {
        site.type = SiteType.publicPark;
      }
    }
    reseedRNG(seed: 587319);
    await sleeperEffect(sleeper, _power()).timeout(const Duration(seconds: 1));
    expect(nextRngSeed, expectedNext);
    expect(engine.console.awaitingInput, isFalse);
    engine.erase();
    displayBlindLog();
    expect(
      engine.console.currentReportText().replaceAll(RegExp(r'\s+'), ' '),
      contains('no homeless dead-drop camp'),
    );
  });

  test(
    'blind exposed spy and thief finish and retain their mechanical outcomes',
    () async {
      game.cantSeeReason = CantSeeReason.hospital;
      final worksite = game.sites.firstWhere(
        (s) => s.type == SiteType.policeStation,
      );
      sleeper
        ..workLocation = worksite
        ..activity = Activity(ActivityType.sleeperSpy)
        ..infiltration = .8;
      final seed = List.generate(
        200,
        (i) => i,
      ).firstWhere((seed) => Random(seed).nextInt(100) > 80);
      reseedRNG(seed: seed);
      await sleeperEffect(
        sleeper,
        _power(),
      ).timeout(const Duration(seconds: 1));
      expect(sleeper.infiltration, closeTo(.75, .000001));
      expect(engine.console.awaitingInput, isFalse);
      engine.erase();
      displayBlindLog();
      expect(
        engine.console.currentReportText(),
        contains('caught snooping around'),
      );

      clearBlindLog();
      sleeper
        ..activity = Activity(ActivityType.sleeperSteal)
        ..infiltration = .8;
      reseedRNG(seed: seed);
      await sleeperEffect(
        sleeper,
        _power(),
      ).timeout(const Duration(seconds: 1));
      expect(sleeper.infiltration, lessThan(.7));
      expect(engine.console.awaitingInput, isFalse);
      engine.erase();
      displayBlindLog();
      expect(
        engine.console.currentReportText(),
        contains('noticed things are going missing'),
      );
    },
  );
}
