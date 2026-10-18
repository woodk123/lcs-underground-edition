import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/monthly/advance_month.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';
import 'package:lcs_new_age/utils/game_version.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:path/path.dart' as paths;
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

final class RecoverySaveDirectory extends IOOverrides {
  RecoverySaveDirectory(this.original, this.isolated);
  final String? original;
  final String isolated;

  @override
  Directory createDirectory(String path) => super.createDirectory(
    original != null && paths.equals(original!, path) ? isolated : path,
  );
}

class FaultInjectingStorage extends SembastStorage {
  bool failWrites = false;
  int failedWrites = 0;
  int lastGameUpdates = 0;

  @override
  Future<void> saveGame(SaveFile saveFile) async {
    if (failWrites) {
      failedWrites++;
      throw const FileSystemException('Storage is full or unavailable.');
    }
    await super.saveGame(saveFile);
  }

  @override
  Future<void> updateLastGameId(String gameId) async {
    lastGameUpdates++;
    await super.updateLastGameId(gameId);
  }
}

class RecoveryResult<T> {
  RecoveryResult(this.value, this.frames);
  final T value;
  final List<String> frames;
}

Future<RecoveryResult<T>> acknowledge<T>(Future<T> Function() operation) async {
  final console = engine.console;
  final frames = <String>[];
  final failed = Completer<T>();
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    final text = console.buffer
        .map((r) => r.map((c) => c.glyph).join())
        .join('\n');
    frames.add(text);
    if (frames.length > 40) {
      if (!failed.isCompleted) {
        failed.completeError(StateError('Recovery prompt loop'));
      }
      return;
    }
    console.sendInput(
      text.contains('The Triumph of the Liberal Agenda') ? 'l' : 'Enter',
    );
  }

  console.revision.addListener(respond);
  try {
    final result = await Future.any([
      operation(),
      failed.future,
    ]).timeout(const Duration(seconds: 10));
    return RecoveryResult(result, frames);
  } finally {
    console.revision.removeListener(respond);
  }
}

Future<SaveFile> fixtureSave(String name) async => SaveFile.fromJson(
  jsonDecode(await File('test/saves/$name').readAsString())
      as Map<String, dynamic>,
);

SaveFile currentSave() => SaveFile(
  version: saveCompatibilityVersion,
  saveData: game.gameState.toJson(),
  gameId: game.gameState.uniqueGameId.toString(),
  lastPlayed: DateTime(2026, 10, 13),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final storage = FaultInjectingStorage();
  late Directory testRoot;
  late String databasePath;

  setUpAll(() async {
    await ensureGameDataLoaded();
    SharedPreferences.setMockInitialValues({});
    testRoot = await Directory.systemTemp.createTemp('lcs-save-recovery-');
    final isolated = paths.join(testRoot.path, 'saves');
    await Directory(isolated).create();
    databasePath = paths.join(isolated, 'lcs_new_age.db');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => isolated,
    );
    final appData = Platform.environment['APPDATA'];
    await IOOverrides.runWithIOOverrides(
      () => initStorage(storage: storage),
      RecoverySaveDirectory(
        appData == null
            ? null
            : paths.join(appData, 'LCS New Age', 'lcs_new_age'),
        isolated,
      ),
    );
    expect(File(databasePath).existsSync(), isTrue);
  });

  tearDownAll(() async {
    await storage.close();
    await testRoot.delete(recursive: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  setUp(() async {
    storage.failWrites = false;
    storage.failedWrites = 0;
    storage.lastGameUpdates = 0;
    for (final id in await storage.listGameIds()) {
      await storage.deleteGame(id);
    }
    SharedPreferences.setMockInitialValues({'lastGameId': 123});
    engine.console = Console();
    final save = await fixtureSave('felix_1_0.json');
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
  });

  test(
    'autosaves retain compatibility independently of the Underground version',
    () async {
      final expected = jsonEncode(game.gameState.toJson());
      expect(await autoSaveGame(), isTrue);
      final stored = (await storage.loadGame(
        game.gameState.uniqueGameId.toString(),
      ))!;
      expect(stored.version, saveCompatibilityVersion);
      final result = await acknowledge(() => loadGameFromSave(stored));
      expect(result.value, isTrue);
      expect(jsonEncode(game.gameState.toJson()), expected);
    },
  );

  test(
    'portable export/import preserves all five normalized shipped campaigns',
    () async {
      for (final fixture in [
        'felix_1_0.json',
        'EQ_1_1.json',
        'ebony_1_2_9.json',
        'eevee_1_4_5.json',
        'moe_1_5.json',
      ]) {
        final old = await fixtureSave(fixture);
        game.gameState = game.GameState.fromJson(old.saveData);
        applyBugFixes(old.version);
        final expected = jsonEncode(game.gameState.toJson());
        final live = game.gameState;
        final exported = encodeSaveContents(currentSave());
        final imported = await acknowledge(
          () => importSaveBytes(utf8.encode(exported)),
        );
        expect(imported.value, isNotNull, reason: fixture);
        expect(imported.frames.join(), contains('Save imported successfully.'));
        expect(
          identical(game.gameState, live),
          isTrue,
          reason: 'Import must not silently switch the current campaign.',
        );
        final stored = (await loadGameList()).singleWhere(
          (save) => save.gameId == live.uniqueGameId.toString(),
        );
        expect(await loadGameFromSave(stored), isTrue);
        expect(jsonEncode(game.gameState.toJson()), expected, reason: fixture);
      }
    },
  );

  for (final input in <String, String>{
    '{"saveData":': 'incomplete or is not valid JSON',
    '[]': 'not a New Age saved campaign',
    '{"version":"1.5.6"}': 'header is missing or damaged',
    '{"version":"1.5.6","gameId":"invalid","saveData":{},"lastPlayed":null}':
        'campaign data is incomplete or damaged',
  }.entries) {
    test(
      'malformed import is readable and preserves the open campaign: ${input.value}',
      () async {
        final before = jsonEncode(game.gameState.toJson());
        final live = game.gameState;
        await storage.saveGame(currentSave());
        final result = await acknowledge(
          () => importSaveBytes(utf8.encode(input.key)),
        );
        expect(result.value, isNull);
        expect(
          result.frames.join(),
          contains('The save could not be imported.'),
        );
        expect(result.frames.join(), contains(input.value));
        expect(
          result.frames.join(),
          isNot(contains('Save imported successfully.')),
        );
        expect(identical(game.gameState, live), isTrue);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(await storage.listGameIds(), [live.uniqueGameId.toString()]);
      },
    );
  }

  for (final version in ['unknown', '99.0.0']) {
    test(
      'unsupported version $version is rejected before overwriting an existing save',
      () async {
        final valid = currentSave();
        await storage.saveGame(valid);
        final exported = valid.toJson()..['version'] = version;
        final result = await acknowledge(
          () => importSaveBytes(utf8.encode(jsonEncode(exported))),
        );
        expect(result.value, isNull);
        expect(
          result.frames.join(),
          contains(
            version == 'unknown'
                ? 'unsupported version label'
                : 'requires New Age 99.0.0 or later',
          ),
        );
        expect(
          encodeSaveContents((await storage.loadGame(valid.gameId))!),
          encodeSaveContents(valid),
        );
      },
    );
  }

  test(
    'invalid UTF-8 is handled without a success message or campaign changes',
    () async {
      final before = jsonEncode(game.gameState.toJson());
      final result = await acknowledge(
        () => importSaveBytes(Uint8List.fromList([0xff, 0xfe])),
      );
      expect(result.value, isNull);
      expect(result.frames.join(), contains('The save could not be imported.'));
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(await storage.listGameIds(), isEmpty);
    },
  );

  test(
    'failed import write retains the previous save and does not report success',
    () async {
      final previous = currentSave();
      await storage.saveGame(previous);
      storage.failWrites = true;
      final result = await acknowledge(
        () => importSaveBytes(utf8.encode(encodeSaveContents(previous))),
      );
      expect(result.value, isNull);
      expect(result.frames.join(), contains('Storage is full or unavailable.'));
      expect(
        result.frames.join(),
        isNot(contains('Save imported successfully.')),
      );
      expect(
        encodeSaveContents((await storage.loadGame(previous.gameId))!),
        encodeSaveContents(previous),
      );
      expect(storage.lastGameUpdates, 0);
    },
  );

  test(
    'failed pre-day autosave leaves date, assignments and finances unchanged',
    () async {
      game.pool.first.activity = Activity(ActivityType.donations);
      final before = jsonEncode(game.gameState.toJson());
      storage.failWrites = true;
      final result = await acknowledge(advanceDay);
      expect(result.value, isFalse);
      expect(
        result.frames.join(),
        contains('Your campaign could not be saved.'),
      );
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(storage.lastGameUpdates, 0);
      expect((await SharedPreferences.getInstance()).getInt('lastGameId'), 123);
    },
  );

  for (final command in ['x', 'w']) {
    test(
      'failed HQ $command command returns to the same campaign before retrying',
      () async {
        // A first-of-month fixture catches accidental monthly processing after a
        // failed pre-day save as well as accidental time or location advancement.
        game.gameState.date = DateTime(2023, 2, 1);
        game.ledger.addFunds(20, Income.donations);
        game.sites.first.closed = 3;
        storage.failWrites = true;
        final console = engine.console;
        final headquartersStates = <String>[];
        final errors = <String>[];
        void respond() {
          if (!console.awaitingInput || console.lastKey != null) return;
          if (console.screen == 'headquarters') {
            headquartersStates.add(jsonEncode(game.gameState.toJson()));
            if (headquartersStates.length == 1) {
              console.sendInput(command);
            } else {
              storage.failWrites = false;
              console.sendInput('x');
            }
          } else {
            errors.add(
              console.buffer
                  .map((r) => r.map((c) => c.glyph).join())
                  .join('\n'),
            );
            console.sendInput('Enter');
          }
        }

        console.revision.addListener(respond);
        try {
          await expectLater(
            baseMode().timeout(const Duration(seconds: 10)),
            throwsA(isA<EndGameException>()),
          );
        } finally {
          console.revision.removeListener(respond);
        }
        expect(headquartersStates, hasLength(2));
        expect(headquartersStates[1], headquartersStates[0]);
        expect(errors.join(), contains('Your campaign could not be saved.'));
        expect(storage.failedWrites, 1);
        expect(storage.lastGameUpdates, 1);
      },
    );
  }

  test(
    'a migration failure rolls back the current campaign instead of replacing it',
    () async {
      final before = jsonEncode(game.gameState.toJson());
      final live = game.gameState;
      final broken = jsonDecode(before) as Map<String, dynamic>;
      for (final city in broken['cities'] as List) {
        for (final district in (city as Map)['districts'] as List) {
          ((district as Map)['sites'] as List).removeWhere(
            (site) => (site as Map)['type'] == 'ceoHouse',
          );
        }
      }
      final result = await acknowledge(
        () => loadGameFromSave(
          SaveFile(
            version: saveCompatibilityVersion,
            gameId: 'broken-world',
            saveData: broken,
            lastPlayed: null,
          ),
        ),
      );
      expect(result.value, isFalse);
      expect(
        result.frames.join(),
        contains('This campaign could not be loaded.'),
      );
      expect(identical(game.gameState, live), isTrue);
      expect(jsonEncode(game.gameState.toJson()), before);
    },
  );

  test(
    'a partially corrupt roster cannot mutate the current campaign while decoding',
    () async {
      final before = jsonEncode(game.gameState.toJson());
      final live = game.gameState;
      final payload = currentSave().toJson();
      final data = jsonDecode(before) as Map<String, dynamic>;
      final roster = (data['lcs'] as Map)['pool'] as List;
      (roster[1] as Map)['body'] = null;
      payload['saveData'] = data;
      final result = await acknowledge(
        () => importSaveBytes(utf8.encode(jsonEncode(payload))),
      );
      expect(result.value, isNull);
      expect(
        result.frames.join(),
        contains('campaign data is incomplete or damaged'),
      );
      expect(identical(game.gameState, live), isTrue);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(await storage.listGameIds(), isEmpty);
    },
  );

  for (final scenario in [
    'valid decode',
    'valid import',
    'partial import failure',
    'load migration failure',
    'save list preview',
  ]) {
    test('$scenario preserves the live campaign random stream', () async {
      final valid = currentSave();
      final data =
          jsonDecode(jsonEncode(game.gameState.toJson()))
              as Map<String, dynamic>;
      if (scenario == 'partial import failure') {
        final roster = (data['lcs'] as Map)['pool'] as List;
        (roster[1] as Map)['body'] = null;
      } else if (scenario == 'load migration failure') {
        for (final city in data['cities'] as List) {
          for (final district in (city as Map)['districts'] as List) {
            ((district as Map)['sites'] as List).removeWhere(
              (site) => (site as Map)['type'] == 'ceoHouse',
            );
          }
        }
      }
      final candidate = SaveFile(
        version: valid.version,
        gameId: valid.gameId,
        saveData: data,
        lastPlayed: valid.lastPlayed,
      );
      if (scenario == 'save list preview') await storage.saveGame(valid);
      reseedRNG(seed: 20261013);
      final expected = List.generate(8, (_) => lcsRandom(1000000));
      reseedRNG(seed: 20261013);
      switch (scenario) {
        case 'valid decode':
          expect(
            decodeSaveContents(encodeSaveContents(candidate)).gameState,
            isNotNull,
          );
        case 'valid import':
          final run = await acknowledge(
            () => importSaveBytes(utf8.encode(encodeSaveContents(candidate))),
          );
          expect(run.value, isNotNull);
        case 'partial import failure':
          final run = await acknowledge(
            () => importSaveBytes(utf8.encode(encodeSaveContents(candidate))),
          );
          expect(run.value, isNull);
        case 'load migration failure':
          final run = await acknowledge(() => loadGameFromSave(candidate));
          expect(run.value, isFalse);
        case 'save list preview':
          expect((await loadGameList()).single.gameState, isNotNull);
      }
      expect(
        List.generate(8, (_) => lcsRandom(1000000)),
        expected,
        reason: 'Save validation must not change upcoming gameplay rolls.',
      );
    });
  }

  test(
    'corrupt records stay isolated and cannot destroy another valid save',
    () async {
      final valid = currentSave();
      await storage.saveGame(valid);
      final database = await databaseFactoryIo.openDatabase(databasePath);
      final records = stringMapStoreFactory.store('saves');
      await records.record('truncated').put(database, {'data': '{"saveData":'});
      await storage.saveGame(
        SaveFile(
          version: saveCompatibilityVersion,
          gameId: 'bad-state',
          saveData: {'cities': []},
          lastPlayed: null,
        ),
      );
      final saves = await loadGameList();
      expect(
        saves.singleWhere((save) => save.gameId == valid.gameId).gameState,
        isNotNull,
      );
      expect(
        saves.singleWhere((save) => save.gameId == 'bad-state').gameState,
        isNull,
      );
      expect(await records.record('truncated').exists(database), isTrue);
      expect(
        encodeSaveContents((await storage.loadGame(valid.gameId))!),
        encodeSaveContents(valid),
      );
      final before = jsonEncode(game.gameState.toJson());
      final result = await acknowledge(
        () => loadGameFromSave(
          saves.singleWhere((save) => save.gameId == 'bad-state'),
        ),
      );
      expect(result.value, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect((await storage.listGameIds()).toSet(), {
        valid.gameId,
        'truncated',
        'bad-state',
      });
    },
  );

  test(
    'real victory gate records a victory, deletes its save and ends the campaign',
    () async {
      for (final law in game.laws.keys.toList()) {
        game.laws[law] = DeepAlignment.eliteLiberal;
      }
      game.court.fillRange(0, game.court.length, DeepAlignment.eliteLiberal);
      game.house.fillRange(0, game.house.length, DeepAlignment.eliteLiberal);
      game.senate.fillRange(0, game.senate.length, DeepAlignment.eliteLiberal);
      for (final office in game.exec.keys.toList()) {
        game.exec[office] = DeepAlignment.eliteLiberal;
      }
      game.ccsState = game.CCSStrength.defeated;
      expect(await autoSaveGame(), isTrue);
      await expectLater(
        acknowledge(winCheck),
        throwsA(isA<EndGameException>()),
      );
      final scores = await loadHighScores();
      expect(scores.universalVictories, 1);
      expect(scores.scoreList.single.endType, Ending.victory);
      expect(await storage.listGameIds(), isEmpty);
    },
  );

  test(
    'real defeat gate records the loss, deletes its save and ends the campaign',
    () async {
      for (final person in game.pool) {
        person.die();
      }
      expect(await autoSaveGame(), isTrue);
      await expectLater(
        acknowledge(() => checkForDefeat(Ending.dead)),
        throwsA(isA<EndGameException>()),
      );
      final scores = await loadHighScores();
      expect(scores.universalLosses, 1);
      expect(scores.scoreList.single.endType, Ending.dead);
      expect(await storage.listGameIds(), isEmpty);
    },
  );
}
