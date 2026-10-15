import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/saveload/load_cpc_images.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:path/path.dart' as paths;
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// Redirects only the native save directory. These tests exercise the actual
/// autosave backend without opening or modifying the player's campaign store.
final class IsolatedSaveDirectory extends IOOverrides {
  IsolatedSaveDirectory(this.originalPath, this.testPath);

  final String? originalPath;
  final String testPath;

  @override
  Directory createDirectory(String path) => super.createDirectory(
    originalPath != null && paths.equals(path, originalPath!) ? testPath : path,
  );
}

class CampaignRun {
  final List<DateTime> headquartersDates = [];
  final List<LedgerReportFrame> monthlyReports = [];
  int dayCommands = 0;
  int exitCommands = 0;
  int acknowledgements = 0;
  int prompts = 0;
}

/// Acts as a player through the original headquarters command loop. It advances
/// only at headquarters and acknowledges engine messages, newspapers and the
/// monthly report. Unknown or looping decisions fail within a bounded budget.
Future<CampaignRun> playUntil(
  DateTime target, {
  int maxPrompts = 1200,
  void Function()? onHeadquarters,
}) async {
  final run = CampaignRun();
  final failed = Completer<void>();
  final console = engine.console;

  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    try {
      if (++run.prompts > maxPrompts) {
        if (!failed.isCompleted) {
          failed.completeError(
            StateError('Exceeded $maxPrompts campaign prompts'),
          );
        }
        return;
      }
      String key;
      final report = ledgerReportFrame(console);
      if (report != null) {
        expect(report.management, isFalse);
        expect(report.navigation, isNull);
        expect(report.closeAction.enabled, isTrue);
        run.monthlyReports.add(report);
      }
      if (console.screen == 'headquarters') {
        run.headquartersDates.add(game.date);
        onHeadquarters?.call();
        if (game.date.isBefore(target)) {
          run.dayCommands++;
          key = console.actions
              .singleWhere((action) => action.key == 'w' && action.enabled)
              .key;
        } else if (game.date == target) {
          run.exitCommands++;
          key = 'x';
        } else {
          if (!failed.isCompleted) {
            failed.completeError(StateError('Campaign skipped past $target'));
          }
          return;
        }
      } else {
        run.acknowledgements++;
        key = 'Enter';
      }
      if (!console.sendInput(key) && !failed.isCompleted) {
        failed.completeError(StateError('Engine rejected prompt input $key'));
      }
    } catch (error, stack) {
      if (!failed.isCompleted) failed.completeError(error, stack);
    }
  }

  console.revision.addListener(respond);
  try {
    final progression = () async {
      try {
        await baseMode();
        throw StateError('Headquarters returned without Save & Exit');
      } on EndGameException {
        if (run.exitCommands != 1) {
          throw StateError('Campaign ended before the requested Save & Exit');
        }
      }
    }();
    await Future.any([progression, failed.future]).timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Campaign stalled at ${game.date}, after ${run.prompts} prompts: '
        '${console.buffer.map((r) => r.map((c) => c.glyph).join()).join('\n')}',
      ),
    );
  } finally {
    console.revision.removeListener(respond);
  }
  return run;
}

/// Enters each order through the original assignment handler and its current
/// source actions. Nested skill/clothing/flag choices remain explicit. This
/// prepares orders only; no day, payment, training or crafting is simulated.
Future<void> assignThroughSource(
  Creature person,
  ActivityType type, {
  Skill? skill,
  String? itemName,
}) async {
  final console = engine.console;
  final failure = Completer<void>();
  var phase = 0;
  var itemSelected = false;
  var prompts = 0;
  final category = switch (type) {
    ActivityType.donations ||
    ActivityType.sellTshirts ||
    ActivityType.sellArt ||
    ActivityType.sellMusic => 'b',
    ActivityType.study || ActivityType.takeClass => 'e',
    ActivityType.makeClothing || ActivityType.makeFlag => 'd',
    ActivityType.communityService || ActivityType.writeGuardian => 'a',
    ActivityType.teachFighting || ActivityType.teachLiberalArts => 't',
    _ => throw ArgumentError('Unsupported acceptance order $type'),
  };

  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    try {
      if (++prompts > 60) throw StateError('Assignment did not settle.');
      final order = activityOrderFrame(console);
      String key;
      if (order != null) {
        expect(order.actorId, person.id);
        if (phase == 0) {
          key = order.categoryPreviewCommands[category]!;
          phase = 1;
        } else if (phase == 1) {
          key = console.actions
              .singleWhere(
                (action) =>
                    action.entityType == 'activity' &&
                    action.entityId == type.name &&
                    action.enabled,
              )
              .key;
          phase = 2;
        } else {
          expect(person.activity.type, type);
          if (skill != null) expect(person.activity.skill, skill);
          if (itemName != null) {
            expect(
              person.activity.clothingType?.name ??
                  person.activity.flagType?.name,
              itemName,
            );
          }
          key = order.confirmation.key;
          phase = 3;
        }
      } else {
        expect(phase, 2, reason: 'Unexpected source reader before selection.');
        final label = skill?.displayName ?? itemName!;
        final matches = console.actions.where(
          (action) =>
              action.enabled &&
              action.label.replaceFirst(RegExp(r'^[A-Za-z] - '), '') == label,
        );
        if (matches.isNotEmpty && (!itemSelected || skill != null)) {
          key = matches.single.key;
          itemSelected = true;
        } else if (itemSelected) {
          key = console.actions
              .singleWhere((action) => action.key == 'Enter' && action.enabled)
              .key;
        } else {
          key = console.actions
              .singleWhere(
                (action) => action.key == 'PageDown' && action.enabled,
              )
              .key;
        }
      }
      if (!console.sendInput(key)) {
        throw StateError('Rejected order input $key.');
      }
    } catch (error, stack) {
      if (!failure.isCompleted) failure.completeError(error, stack);
    }
  }

  console.revision.addListener(respond);
  try {
    await Future.any([
      assignTask(person),
      failure.future,
    ]).timeout(const Duration(seconds: 10));
  } finally {
    console.revision.removeListener(respond);
  }
  expect(phase, 3);
  expect(console.awaitingInput, isFalse);
}

Future<void> expectPersistedCampaign() async {
  final before = jsonEncode(game.gameState.toJson());
  final saves = await loadGameList();
  final saved = saves.singleWhere(
    (save) => save.gameId == game.gameState.uniqueGameId.toString(),
  );
  expect(saved.gameState, isNotNull);
  game.gameState = game.GameState.fromJson(saved.saveData);
  expect(
    jsonEncode(game.gameState.toJson()),
    before,
    reason: 'The real Save & Exit must retain all progressed campaign data.',
  );
  final reloaded = jsonEncode(game.gameState.toJson());
  game.gameState = game.GameState.fromJson(
    jsonDecode(reloaded) as Map<String, dynamic>,
  );
  expect(jsonEncode(game.gameState.toJson()), reloaded);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testRoot;
  late String databasePath;

  setUpAll(() async {
    await ensureGameDataLoaded();
    await loadCpcGraphics();
    SharedPreferences.setMockInitialValues({});
    testRoot = await Directory.systemTemp.createTemp(
      'lcs-campaign-progression-',
    );
    final saveDirectory = paths.join(testRoot.path, 'saves');
    await Directory(saveDirectory).create();
    databasePath = paths.join(saveDirectory, 'lcs_new_age.db');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => saveDirectory,
    );
    final appData = Platform.environment['APPDATA'];
    await IOOverrides.runWithIOOverrides(
      initStorage,
      IsolatedSaveDirectory(
        appData == null
            ? null
            : paths.join(appData, 'LCS New Age', 'lcs_new_age'),
        saveDirectory,
      ),
    );
    expect(
      File(databasePath).existsSync(),
      isTrue,
      reason: 'Autosaves must use the isolated temporary database.',
    );
  });

  tearDownAll(() async {
    await databaseFactoryIo.deleteDatabase(databasePath);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await testRoot.delete(recursive: true);
  });

  setUp(() async {
    engine.console = Console();
    final raw =
        jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
            as Map<String, dynamic>;
    final save = SaveFile.fromJson(raw);
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    reseedRNG(seed: 20261013);
    // Assign tasks available to the real fixture roster. No money, health,
    // laws, dates or other gameplay outcomes are changed by the test setup.
    game.pool[0].activity = Activity(ActivityType.donations);
    game.pool[1].activity = Activity(ActivityType.study, skill: Skill.science);
  });

  test(
    'one headquarters day executes tasks, ages roster once and persists',
    () async {
      final start = game.date;
      final funds = game.ledger.funds;
      final ageBefore = {
        for (final person in game.pool) person.id: person.daysSinceJoined,
      };
      final peopleBefore = game.pool.map((person) => person.id).toSet();
      final learner = game.pool[1];
      final skillBefore = learner.skill(Skill.science);
      final experienceBefore = learner.skillXP(Skill.science);
      final run = await playUntil(start.add(const Duration(days: 1)));

      expect(run.dayCommands, 1);
      expect(run.exitCommands, 1);
      expect(run.headquartersDates, [
        start,
        start.add(const Duration(days: 1)),
      ]);
      expect(game.date, start.add(const Duration(days: 1)));
      expect(game.pool.map((person) => person.id).toSet(), peopleBefore);
      for (final person in game.pool) {
        expect(person.daysSinceJoined, ageBefore[person.id]! + 1);
        expect(person.base?.controller, SiteController.lcs);
      }
      expect(game.pool[0].activity.type, ActivityType.donations);
      expect(game.pool[0].income, greaterThan(0));
      expect(game.ledger.dailyIncome[Income.donations], game.pool[0].income);
      expect(game.ledger.funds, greaterThan(funds));
      expect(
        learner.skill(Skill.science) > skillBefore ||
            learner.skill(Skill.science) == skillBefore &&
                learner.skillXP(Skill.science) > experienceBefore,
        isTrue,
        reason: 'The study assignment must actually advance science training.',
      );
      expect(engine.console.screen, 'generic');
      expect(engine.console.awaitingInput, isFalse);
      await expectPersistedCampaign();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a retained campaign reaches next month without duplicate days or data loss',
    () async {
      final start = game.date;
      final target = DateTime(start.year, start.month + 1, 1);
      final days = target.difference(start).inDays;
      final peopleBefore = game.pool.map((person) => person.id).toSet();
      final ageBefore = {
        for (final person in game.pool) person.id: person.daysSinceJoined,
      };
      final squadBefore = game.squads.single.members
          .map((person) => person.id)
          .toSet();
      final run = await playUntil(target);

      expect(run.dayCommands, days);
      expect(run.exitCommands, 1);
      expect(
        run.acknowledgements,
        greaterThan(0),
        reason:
            'The retained newspaper/monthly result screens must be exercised.',
      );
      expect(
        run.headquartersDates,
        List.generate(days + 1, (i) => start.add(Duration(days: i))),
      );
      expect(game.date, target);
      expect(game.pool.map((person) => person.id).toSet(), peopleBefore);
      expect(
        game.squads.single.members.map((person) => person.id).toSet(),
        squadBefore,
      );
      for (final person in game.pool) {
        expect(person.daysSinceJoined, ageBefore[person.id]! + days);
        expect(person.alive, isTrue);
        expect(person.base?.controller, SiteController.lcs);
      }
      expect(game.ledger.totalIncome, greaterThan(0));
      expect(
        game.ledger.income.values.every((amount) => amount == 0),
        isTrue,
        reason: 'The first-of-month financial cycle must reset monthly income.',
      );
      expect(game.ledger.expense.values.every((amount) => amount == 0), isTrue);
      expect(game.gameState.newsArchive, isNotEmpty);
      expect(engine.console.screen, 'generic');
      expect(engine.console.awaitingInput, isFalse);
      await expectPersistedCampaign();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '31 varied days retain accounting, original order choices and a mid-month save',
    () async {
      final start = game.date;
      final target = start.add(const Duration(days: 31));
      final startingFunds = game.ledger.funds;
      final startingIncome = game.ledger.totalIncome;
      final startingExpense = game.ledger.totalExpense;
      final roster = game.pool.map((person) => person.id).toSet();
      final memberIds = game.squads.single.members
          .map((person) => person.id)
          .toSet();
      final joined = {
        for (final person in game.pool) person.id: person.daysSinceJoined,
      };
      final learnerId = game.pool[1].id;
      final scienceBefore = game.pool[1].skill(Skill.science);
      final scienceXpBefore = game.pool[1].skillXP(Skill.science);
      final tailoringBefore = game.pool[3].skillXP(Skill.tailoring);
      final days = <DateTime>[];
      final incomeKinds = <Income>{};
      final expenseKinds = <Expense>{};
      final reports = <LedgerReportFrame>[];
      var commands = 0;
      var exits = 0;
      var lastRecorded = start;

      void recordHeadquarters() {
        expect(headquartersFrame(engine.console)?.matchesCurrentGame, isTrue);
        expect(
          game.ledger.funds,
          startingFunds +
              game.ledger.totalIncome -
              startingIncome -
              (game.ledger.totalExpense - startingExpense),
        );
        expect(game.pool.map((person) => person.id).toSet(), roster);
        for (final person in game.pool) {
          expect(person.alive, isTrue);
          expect(
            person.daysSinceJoined,
            joined[person.id]! + game.date.difference(start).inDays,
          );
        }
        if (game.date == lastRecorded) return;
        expect(game.date, lastRecorded.add(const Duration(days: 1)));
        days.add(game.date);
        incomeKinds.addAll(
          game.ledger.dailyIncome.entries
              .where((entry) => entry.value > 0)
              .map((entry) => entry.key),
        );
        expenseKinds.addAll(
          game.ledger.dailyExpense.entries
              .where((entry) => entry.value > 0)
              .map((entry) => entry.key),
        );
        if (game.date.day == 1) {
          expect(
            game.ledger.income.values.every((amount) => amount == 0),
            isTrue,
          );
          expect(
            game.ledger.expense.values.every((amount) => amount == 0),
            isTrue,
          );
        }
        lastRecorded = game.date;
      }

      // The unchanged five-person fixture funds its paid training and supplies
      // through real fundraising. Each block explicitly chooses its source
      // orders; no skill, money, law, date or result is altered by the fixture.
      final blockLengths = [4, 4, 4, 3, 4, 4, 4, 4];
      var elapsed = 0;
      for (var block = 0; block < blockLengths.length; block++) {
        final crew = game.pool;
        await assignThroughSource(
          crew[0],
          block == 2 ? ActivityType.teachFighting : ActivityType.donations,
        );
        await assignThroughSource(
          crew[1],
          block == 1 || block == 5
              ? ActivityType.takeClass
              : ActivityType.study,
          skill: block == 2 || block == 6 ? Skill.tailoring : Skill.science,
        );
        await assignThroughSource(
          crew[2],
          block == 3 || block == 7
              ? ActivityType.communityService
              : ActivityType.sellTshirts,
        );
        await assignThroughSource(
          crew[3],
          block == 1 || block == 4
              ? ActivityType.makeClothing
              : block == 3
              ? ActivityType.writeGuardian
              : ActivityType.sellArt,
          itemName: block == 1 || block == 4 ? 'Clothes' : null,
        );
        await assignThroughSource(
          crew[4],
          block == 2 || block == 6
              ? ActivityType.makeFlag
              : ActivityType.sellMusic,
          itemName: block == 2 || block == 6 ? 'Rainbow Pride Flag' : null,
        );

        elapsed += blockLengths[block];
        final run = await playUntil(
          start.add(Duration(days: elapsed)),
          onHeadquarters: recordHeadquarters,
        );
        commands += run.dayCommands;
        exits += run.exitCommands;
        reports.addAll(run.monthlyReports);
        await expectPersistedCampaign();
        if (block == 3) {
          expect(game.date, start.add(const Duration(days: 15)));
          final learner = game.pool.singleWhere(
            (person) => person.id == learnerId,
          );
          expect(
            learner.skill(Skill.science) > scienceBefore ||
                learner.skillXP(Skill.science) > scienceXpBefore,
            isTrue,
            reason:
                'Practice/classes must retain actual progress on reload, '
                'without promising a whole level while cash is limited.',
          );
        }
      }

      expect(game.date, target);
      expect(commands, 31);
      expect(exits, blockLengths.length);
      expect(
        days,
        List.generate(31, (index) => start.add(Duration(days: index + 1))),
      );
      expect(
        game.squads.single.members.map((person) => person.id).toSet(),
        memberIds,
      );
      expect(
        incomeKinds,
        containsAll([
          Income.donations,
          Income.tshirts,
          Income.artSales,
          Income.busking,
        ]),
      );
      expect(
        expenseKinds,
        containsAll([Expense.training, Expense.sewingSupplies]),
      );
      expect(
        game.pool[3].skillXP(Skill.tailoring) > tailoringBefore ||
            game.pool[3].skill(Skill.tailoring) > 0,
        isTrue,
      );
      expect(game.squad.first.site!.loot.whereType<Item>(), isNotEmpty);
      expect(reports, hasLength(1));
      expect(
        reports.single.lines.map((line) => line.id),
        containsAll([
          'income:donations',
          'income:tshirts',
          'income:artSales',
          'income:busking',
          'expense:training',
          'expense:sewingSupplies',
        ]),
      );
      expect(engine.console.awaitingInput, isFalse);
      await expectPersistedCampaign();
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
