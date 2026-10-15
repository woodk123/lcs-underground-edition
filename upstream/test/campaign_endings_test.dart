import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/monthly/advance_month.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/load_cpc_images.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:path/path.dart' as paths;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// Only redirects the native game's directory, leaving fixture/assets reads
/// unchanged and the player's actual campaign database untouched.
final class EndingSaveDirectory extends IOOverrides {
  EndingSaveDirectory(this.originalPath, this.testPath);

  final String? originalPath;
  final String testPath;

  @override
  Directory createDirectory(String path) => super.createDirectory(
    originalPath != null && paths.equals(path, originalPath!) ? testPath : path,
  );
}

class EndingRun {
  final frames = <String>[];
  final semanticChoices = <String>[];
  int prompts = 0;
  int endGameExceptions = 0;
  int titleVisits = 0;
  bool? titleContinueEnabled;
  bool? titleScoresEnabled;
}

class MultiMonthRun {
  final headquartersDates = <DateTime>[];
  final legislationDates = <DateTime>[];
  int prompts = 0;
  int exitCommands = 0;
}

Future<MultiMonthRun> playAcrossMonths(DateTime target) async {
  final run = MultiMonthRun();
  final console = engine.console;
  final failed = Completer<void>();
  void fail(String message) {
    if (!failed.isCompleted) failed.completeError(StateError(message));
  }

  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    if (++run.prompts > 3000) {
      fail('Campaign exceeded 3000 decisions before $target.');
      return;
    }
    final frame = console.buffer
        .map((row) => row.map((cell) => cell.glyph).join())
        .join('\n');
    if (frame.contains('Congress is acting on legislation!')) {
      run.legislationDates.add(DateTime(game.year, game.month, game.day));
    }
    String key = 'Enter';
    if (console.screen == 'headquarters') {
      run.headquartersDates.add(game.date);
      final calendarDay = DateTime(game.year, game.month, game.day);
      if (calendarDay.isBefore(target)) {
        final wait = console.actions.where(
          (action) => action.key == 'w' && action.enabled,
        );
        if (wait.isEmpty) {
          fail('The campaign cannot advance at ${game.date}: $frame');
          return;
        }
        key = wait.single.key;
      } else if (calendarDay == target) {
        key = console.actions.singleWhere((action) => action.key == 'x').key;
        run.exitCommands++;
      } else {
        fail('Campaign advanced beyond $target.');
        return;
      }
    }
    if (!console.sendInput(key)) fail('Campaign rejected input $key.');
  }

  console.revision.addListener(respond);
  try {
    final progression = () async {
      try {
        await baseMode();
        throw StateError('Headquarters returned without its exit route.');
      } on EndGameException {
        if (run.exitCommands != 1) {
          throw StateError('Campaign ended before the requested Save & Exit.');
        }
      }
    }();
    await Future.any([progression, failed.future]).timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Campaign stalled at ${game.date}, after ${run.prompts} prompts.',
      ),
    );
  } finally {
    console.revision.removeListener(respond);
  }
  return run;
}

/// Responds through the same semantic commands used by the modern UI. The
/// victory agenda must expose its real L action; an empty message/high-score
/// action list uses the modern Continue command. The title must expose H.
Future<EndingRun> finishAndReturnToTitle(Future<void> Function() route) async {
  final run = EndingRun();
  final failed = Completer<void>();
  final console = engine.console;

  void fail(String message) {
    if (!failed.isCompleted) failed.completeError(StateError(message));
  }

  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    if (++run.prompts > 64) {
      fail('Ending exceeded 64 decisions: ${run.frames.lastOrNull}');
      return;
    }
    final frame = console.buffer
        .map((row) => row.map((cell) => cell.glyph).join().trimRight())
        .join('\n');
    run.frames.add(frame);
    String key = 'Enter';
    if (console.screen == 'title') {
      run.titleVisits++;
      final scores = console.actions.singleWhere((a) => a.key == 'h');
      run.titleScoresEnabled = scores.enabled;
      run.titleContinueEnabled = console.actions
          .singleWhere((a) => a.key == 'c')
          .enabled;
      if (!scores.enabled) {
        fail('Completed ending was not available through title high scores.');
        return;
      }
      key = scores.key;
      run.semanticChoices.add(key);
    } else if (frame.contains('The Triumph of the Liberal Agenda')) {
      final scores = console.actions.singleWhere((a) => a.key == 'l');
      if (!scores.enabled) {
        fail('Victory high-score choice was disabled.');
        return;
      }
      key = scores.key;
      run.semanticChoices.add(key);
    } else {
      final enterActions = console.actions.where(
        (action) => action.key == 'Enter' && action.enabled,
      );
      if (console.actions.isNotEmpty && enterActions.isEmpty) {
        fail('Unrecognized ending decision: $frame');
        return;
      }
    }
    if (!console.sendInput(key)) fail('Ending rejected semantic input $key.');
  }

  console.revision.addListener(respond);
  try {
    final progression = () async {
      try {
        await route();
        throw StateError(
          'The engine ending returned without EndGameException.',
        );
      } on EndGameException {
        run.endGameExceptions++;
      }
      // launchGame catches this exact exception before calling titleScreen
      // again. Invoke that original entry directly to keep this test bounded.
      await titleScreen();
    }();
    await Future.any([progression, failed.future]).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Ending stalled after ${run.prompts} prompts: ${run.frames.lastOrNull}',
      ),
    );
  } finally {
    console.revision.removeListener(respond);
  }
  return run;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testRoot;
  late SembastStorage storage;

  setUpAll(() async {
    await ensureGameDataLoaded();
    await loadCpcGraphics();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testRoot = await Directory.systemTemp.createTemp('lcs-ending-');
    final saveDirectory = paths.join(testRoot.path, 'saves');
    await Directory(saveDirectory).create();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => saveDirectory,
    );
    storage = SembastStorage();
    final appData = Platform.environment['APPDATA'];
    await IOOverrides.runWithIOOverrides(
      () => initStorage(storage: storage),
      EndingSaveDirectory(
        appData == null
            ? null
            : paths.join(appData, 'LCS New Age', 'lcs_new_age'),
        saveDirectory,
      ),
    );
    expect(
      File(paths.join(saveDirectory, 'lcs_new_age.db')).existsSync(),
      isTrue,
    );
    engine.console = Console();
    final save = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
          as Map<String, dynamic>,
    );
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    reseedRNG(seed: 20261013);
    for (final person in game.pool) {
      person.activity = Activity(ActivityType.none);
    }
  });

  tearDown(() async {
    await storage.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await testRoot.delete(recursive: true);
  });

  Future<HighScore> expectPersistedEnding(Ending ending, EndingRun run) async {
    expect(run.endGameExceptions, 1);
    expect(run.titleVisits, 1);
    expect(run.titleContinueEnabled, isFalse);
    expect(run.titleScoresEnabled, isTrue);
    expect(run.semanticChoices, contains('h'));
    expect(
      await loadGameList(),
      isEmpty,
      reason: 'Completed campaigns must be removed from the real save store.',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('scoreVersion'), scoreVersion);
    final scores = HighScores.fromJson(
      jsonDecode(prefs.getString('score')!) as Map<String, dynamic>,
    );
    expect(scores.scoreList, hasLength(1));
    final score = scores.scoreList.single;
    expect(score.endType, ending);
    expect(score.slogan, game.slogan);
    expect(score.month, game.month);
    expect(score.year, game.year);
    expect(score.statRecruits, game.stats.recruits);
    expect(score.statMartyrs, game.stats.martyrs);
    expect(score.statFunds, game.ledger.totalIncome);
    expect(score.statSpent, game.ledger.totalExpense);
    expect(scores.universalVictories, ending == Ending.victory ? 1 : 0);
    expect(scores.universalLosses, ending == Ending.victory ? 0 : 1);
    expect(scores.universalRecruits, game.stats.recruits);
    expect(scores.universalMartyrs, game.stats.martyrs);
    expect(scores.universalKills, game.stats.kills);
    expect(scores.universalKidnappings, game.stats.kidnappings);
    expect(scores.universalFunds, game.ledger.totalIncome);
    expect(scores.universalSpent, game.ledger.totalExpense);
    expect(scores.universalFlagBuys, game.stats.flagsBought);
    expect(scores.universalFlagBurns, game.stats.flagsBurned);
    expect(engine.console.awaitingInput, isFalse);
    return score;
  }

  test(
    'monthly victory persists its score, deletes the save and returns to title',
    () async {
      // Explicit end-state fixture, not a claim that test commands earned these
      // outcomes: every law, body and executive is Elite Liberal, CCS defeated.
      game.gameState.date = DateTime(2023, 2, 1);
      game.laws.updateAll((law, alignment) => DeepAlignment.eliteLiberal);
      game.house.fillRange(0, game.house.length, DeepAlignment.eliteLiberal);
      game.senate.fillRange(0, game.senate.length, DeepAlignment.eliteLiberal);
      game.court.fillRange(0, game.court.length, DeepAlignment.eliteLiberal);
      game.exec.updateAll((office, alignment) => DeepAlignment.eliteLiberal);
      game.publicOpinion.updateAll((view, value) => 100);
      game.ccsState = game.CCSStrength.defeated;
      expect(await autoSaveGame(), isTrue);
      expect(await loadGameList(), hasLength(1));

      final run = await finishAndReturnToTitle(advanceMonth);

      expect(run.semanticChoices, ['l', 'h']);
      expect(run.frames.any((f) => f.contains('Congress is acting')), isTrue);
      expect(run.frames.any((f) => f.contains('The Triumph')), isTrue);
      expect(
        run.frames.any((f) => f.contains('liberalized the country')),
        isTrue,
      );
      await expectPersistedEnding(Ending.victory, run);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'roster defeat persists its score, deletes the save and returns to title',
    () async {
      // A valid terminal roster state: the engine's own death method records
      // deaths and health. No surviving liberal remains to prevent defeat.
      for (final person in List.of(game.pool)) {
        if (person.alive) person.die();
        person.squad = null;
        person.location = null;
      }
      expect(game.pool.every((person) => !person.alive), isTrue);
      expect(await autoSaveGame(), isTrue);
      expect(await loadGameList(), hasLength(1));

      final run = await finishAndReturnToTitle(() async {
        await checkForDefeat();
      });

      expect(run.semanticChoices, ['h']);
      expect(run.frames.any((f) => f.contains('was KIA')), isTrue);
      expect(run.frames.any((f) => f.contains('The Triumph')), isFalse);
      await expectPersistedEnding(Ending.dead, run);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'headquarters campaign executes three monthly political cycles and reloads',
    () async {
      // Only valid player task selections are changed. Dates, money, health,
      // political alignments and simulation results remain authoritative.
      game.pool[0].activity = Activity(ActivityType.donations);
      game.pool[1].activity = Activity(
        ActivityType.study,
        skill: Skill.science,
      );
      final start = game.date;
      final target = DateTime(start.year, start.month + 3, 1);
      // Count calendar days independently of the host's daylight-saving time.
      final days = DateTime.utc(
        target.year,
        target.month,
        target.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      final politicalBefore = jsonEncode(game.politics.toJson());
      final rosterBefore = game.pool.map((person) => person.id).toSet();
      final ageBefore = {
        for (final person in game.pool) person.id: person.daysSinceJoined,
      };
      final run = await playAcrossMonths(target);

      expect(run.exitCommands, 1);
      expect(
        run.headquartersDates,
        List.generate(
          days + 1,
          (offset) => DateTime(start.year, start.month, start.day + offset),
        ),
      );
      expect(run.legislationDates, [
        for (var offset = 1; offset <= 3; offset++)
          DateTime(start.year, start.month + offset, 1),
      ]);
      expect(DateTime(game.year, game.month, game.day), target);
      expect(game.pool.map((person) => person.id).toSet(), rosterBefore);
      for (final person in game.pool) {
        expect(person.daysSinceJoined, ageBefore[person.id]! + days);
        expect(person.alive, isTrue);
      }
      expect(
        jsonEncode(game.politics.toJson()),
        isNot(politicalBefore),
        reason: 'The real monthly political simulation must execute.',
      );
      expect(game.gameState.newsArchive, isNotEmpty);
      final beforeReload = jsonEncode(game.gameState.toJson());
      final saved = (await loadGameList()).single;
      expect(saved.gameState, isNotNull);
      game.gameState = game.GameState.fromJson(saved.saveData);
      expect(jsonEncode(game.gameState.toJson()), beforeReload);
      expect(
        (await loadHighScores()).scoreList,
        isEmpty,
        reason: 'Normal progression must not record a false ending.',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  for (final (name, current, expected) in [
    ('spring', DateTime(2023, 3, 26), DateTime(2023, 3, 27)),
    ('autumn', DateTime(2023, 10, 29), DateTime(2023, 10, 30)),
  ]) {
    test('$name daylight-saving transition advances one calendar day', () {
      final next = nextCampaignDay(current);
      expect(next, expected);
      expect(next.hour, 0);
      expect(next.minute, 0);
      expect(next.isUtc, isFalse);
      final utc = DateTime.utc(current.year, current.month, current.day);
      expect(
        nextCampaignDay(utc),
        DateTime.utc(expected.year, expected.month, expected.day),
      );
      expect(nextCampaignDay(utc).isUtc, isTrue);
    });
  }

  test(
    'completed totals exclude unrelated active campaigns until display',
    () async {
      final recruits = game.stats.recruits;
      expect(await autoSaveGame(), isTrue);
      final companion =
          jsonDecode(jsonEncode(game.gameState.toJson()))
              as Map<String, dynamic>;
      companion['uniqueGameId'] = game.gameState.uniqueGameId + 1;
      (companion['stats'] as Map<String, dynamic>)['recruits'] = 99;
      await storage.saveGame(
        SaveFile(
          version: gameVersion,
          saveData: companion,
          gameId: companion['uniqueGameId'].toString(),
          lastPlayed: DateTime(2026, 10, 13),
        ),
      );

      await saveHighScore(Ending.dispersed);
      await deleteSaveGame();

      final prefs = await SharedPreferences.getInstance();
      final persisted = HighScores.fromJson(
        jsonDecode(prefs.getString('score')!) as Map<String, dynamic>,
      );
      expect(
        persisted.universalRecruits,
        recruits,
        reason: 'Only the completed campaign belongs in persisted totals.',
      );
      expect(persisted.scoreList.single.endType, Ending.dispersed);
      final displayed = await loadHighScores();
      expect(
        displayed.universalRecruits,
        recruits + 99,
        reason: 'The live display includes the other active campaign once.',
      );
      expect(
        jsonEncode((await loadGameList()).single.saveData),
        jsonEncode(companion),
      );
    },
  );
}
