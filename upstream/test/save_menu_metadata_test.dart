import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/devtools/development_bridge.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/modern_app.dart' show buildModernTheme;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/utils/game_version.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

class _SaveStorage implements GameStorage {
  final records = <String, String>{};

  @override
  Future<void> init() async {}
  @override
  Future<void> close() async {}
  @override
  Future<List<String>> listGameIds() async => records.keys.toList();
  @override
  Future<SaveFile?> loadGame(String id) async => records.containsKey(id)
      ? SaveFile.fromJson(jsonDecode(records[id]!) as Map<String, dynamic>)
      : null;
  @override
  Future<void> saveGame(SaveFile save) async {
    records[save.gameId] = encodeSaveContents(save);
  }

  @override
  Future<void> deleteGame(String id) async => records.remove(id);
  @override
  Future<void> updateLastGameId(String id) async {}
}

class _SaveMenu {
  _SaveMenu() {
    future = loadGameMenu().then(
      (result) {
        completed = true;
        return result;
      },
      onError: (Object failure, StackTrace stack) {
        completed = true;
        error = failure;
        return false;
      },
    );
  }

  late final Future<bool> future;
  bool completed = false;
  Object? error;

  Future<void> ready({
    bool Function()? when,
    Future<void> Function()? pump,
  }) async {
    for (var count = 0; count < 100; count++) {
      if (engine.console.awaitingInput &&
          engine.console.lastKey == null &&
          (when?.call() ?? true)) {
        return;
      }
      expect(
        completed,
        false,
        reason: 'Save reader ended before its next input: $error',
      );
      await (pump?.call() ?? Future<void>.delayed(Duration.zero));
    }
    fail('The original save reader did not reach the expected input.');
  }

  Future<void> stop({Future<void> Function()? pump}) async {
    for (var count = 0; count < 30 && !completed; count++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Enter');
      await (pump?.call() ?? Future<void>.delayed(Duration.zero));
    }
    expect(
      completed,
      true,
      reason: 'Close the original reader before ending the test.',
    );
    expect(error, isNull);
    await future;
  }
}

List<Map<String, dynamic>> _actions(Map<String, dynamic> observation) =>
    (observation['actions'] as List).cast<Map<String, dynamic>>();

Future<Map<String, dynamic>> _request(
  DevelopmentBridge bridge,
  String method, [
  Map<String, dynamic> params = const {},
]) async => jsonDecode(
  await bridge.request(jsonEncode({'method': method, 'params': params})),
) as Map<String, dynamic>;

Future<Map<String, dynamic>> _act(
  DevelopmentBridge bridge,
  Map<String, dynamic> observation,
  Map<String, dynamic> action,
) => _request(bridge, 'act', {
  'revision': observation['revision'],
  'actionId': action['id'],
});

String _paint(Console console) => jsonEncode([
  for (final row in console.buffer)
    for (final cell in row)
      [
        cell.glyph,
        cell.foreground.toARGB32(),
        cell.background.toARGB32(),
        cell.mouseClickKey,
        cell.noHighlight,
      ],
]);

Console _withoutEntityMetadata(Console source) {
  final copy = Console()..screen = source.screen;
  for (var y = 0; y < source.height; y++) {
    copy.buffer[y].setAll(0, source.buffer[y]);
  }
  copy.actions.addAll([
    for (final action in source.actions)
      ConsoleAction(
        key: action.key,
        label: action.label,
        enabled: action.enabled,
        y: action.y,
        x: action.x,
        width: action.width,
        intentLabel: action.intentLabel,
      ),
  ]);
  return copy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late _SaveStorage storage;
  late DevelopmentBridge bridge;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      font.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await font.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'has_migrated_to_indexeddb': true});
    storage = _SaveStorage();
    await initStorage(storage: storage);
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    bridge = DevelopmentBridge(console: () => engine.console);
    bridge.attachUi(
      Object(),
      blockedReason: () => null,
      inputText: (_, _) async => false,
    );
  });

  Future<void> saveSlots(int count, {bool brokenLast = false}) async {
    for (var index = 0; index < count; index++) {
      final data = jsonDecode(
        jsonEncode(game.gameState.toJson()),
      ) as Map<String, dynamic>;
      data['uniqueGameId'] = 9000 + index;
      data['date'] = DateTime(2023, 1, index + 1).toIso8601String();
      final roster = (data['lcs'] as Map<String, dynamic>)['pool'] as List;
      (roster.first as Map<String, dynamic>)['name'] = 'Shared Founder';
      await storage.saveGame(
        SaveFile(
          version: saveCompatibilityVersion,
          saveData: brokenLast && index == count - 1 ? {'cities': []} : data,
          gameId: '${9000 + index}',
          lastPlayed: index == count - 1 ? null : DateTime(2026, 10, 20),
        ),
      );
    }
  }

  test('actual save slots expose existing identity while inspection preserves the reader and RNG', () async {
    await saveSlots(3, brokenLast: true);
    final state = jsonEncode(game.gameState.toJson());
    final stored = Map.of(storage.records);
    reseedRNG(seed: 7301);
    final expectedRandom = List.generate(8, (_) => lcsRandom(1000000));
    reseedRNG(seed: 7301);
    final menu = _SaveMenu();
    try {
      await menu.ready();
      final console = engine.console;
      final paint = _paint(console), revision = console.revision.value;
      final choices = List.of(console.actions), pending = console.nextKeyEvent;
      final observation = bridge.observe();
      final saves = _actions(observation)
          .where((a) => a['entityType'] == 'save')
          .toList();
      expect(saves.map((a) => a['entityId']), ['9000', '9001', '9002']);
      expect(saves.map((a) => a['entityLabel']), [
        'Shared Founder · Jan 1, 2023',
        'Shared Founder · Jan 2, 2023',
        'Unavailable - check save details · Error',
      ]);
      expect(saves.map((a) => a['label']), ['A -', 'B -', 'C -']);
      expect(saves.map((a) => a['key']), ['a', 'b', 'c']);
      expect(saves.every((a) => a['enabled'] == true), true);
      expect(
        saves.every(
          (a) =>
              !a.containsKey('intentLabel') && !a.containsKey('entityCategory'),
        ),
        true,
      );
      expect(
        console.actions
            .where((a) => a.entityType == 'save')
            .map((a) => (a.y, a.x, a.width)),
        [(2, 0, 4), (3, 0, 4), (4, 0, 4)],
      );
      expect(
        _actions(observation)
            .singleWhere((a) => a['key'] == 'Enter')
            .containsKey('entityLabel'),
        false,
      );
      for (var repeat = 0; repeat < 3; repeat++) {
        expect(bridge.observe(), observation);
        expect((await _request(bridge, 'inspect'))['ok'], true);
      }
      expect(_paint(console), paint);
      expect(console.revision.value, revision);
      expect(console.actions, orderedEquals(choices));
      expect(identical(console.nextKeyEvent, pending), true);
      expect(console.lastKey, isNull);
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(storage.records, stored);
      expect(List.generate(8, (_) => lcsRandom(1000000)), expectedRandom);

      expect((await _act(bridge, observation, saves[1]))['ok'], true);
      await menu.ready(when: () => console.actions.any((a) => a.key == 'l'));
      expect(
        jsonEncode(game.gameState.toJson()),
        state,
        reason: 'Selecting a slot only opens its original management reader.',
      );
      final manage = bridge.observe();
      final load = _actions(manage).singleWhere((a) => a['key'] == 'l');
      expect(
        load.containsKey('entityLabel'),
        false,
        reason: 'Save-row identity must not leak into the child reader.',
      );
      expect((await _act(bridge, manage, load))['ok'], true);
      expect(await menu.future, true);
      expect(game.gameState.uniqueGameId, 9001);
      expect(game.date, DateTime(2023, 1, 2));
      expect(storage.records, stored);
    } finally {
      await menu.stop();
    }
  });

  test('paging retains storage IDs when row keys repeat and rejects the preceding reader', () async {
    await saveSlots(21);
    final state = jsonEncode(game.gameState.toJson());
    final stored = Map.of(storage.records);
    final menu = _SaveMenu();
    try {
      await menu.ready();
      final first = bridge.observe();
      final firstSave = _actions(first)
          .firstWhere((a) => a['entityType'] == 'save');
      final next = _actions(first).singleWhere((a) => a['key'] == ']');
      expect((await _act(bridge, first, next))['ok'], true);
      await menu.ready(
        when: () => engine.console.actions.any((a) => a.entityId == '9020'),
      );
      final second = bridge.observe();
      final secondSave = _actions(second)
          .singleWhere((a) => a['entityType'] == 'save');
      expect(secondSave['key'], firstSave['key']);
      expect(secondSave['entityId'], '9020');
      expect(secondSave['entityLabel'], 'Shared Founder · Jan 21, 2023');
      expect(secondSave['id'], isNot(firstSave['id']));
      expect(second['revision'], isNot(first['revision']));
      final obsoleteRevision = await _act(bridge, first, firstSave);
      expect((obsoleteRevision['error'] as Map)['code'], 'stale_revision');
      final obsoleteAction = await _act(bridge, second, firstSave);
      expect((obsoleteAction['error'] as Map)['code'], 'stale_action');
      expect(engine.console.lastKey, isNull);
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(storage.records, stored);
      expect((await _act(bridge, second, secondSave))['ok'], true);
      await menu.ready(
        when: () => engine.console.actions.any((a) => a.key == 'l'),
      );
      final manage = bridge.observe();
      expect(
        (await _act(
          bridge,
          manage,
          _actions(manage).singleWhere((a) => a['key'] == 'l'),
        ))['ok'],
        true,
      );
      expect(await menu.future, true);
      expect(game.gameState.uniqueGameId, 9020);
      expect(game.date, DateTime(2023, 1, 21));
    } finally {
      await menu.stop();
    }
  });

  for (final layout in [
    (const Size(1440, 1000), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    testWidgets(
      'save identity leaves direct rendering and semantics identical at $layout',
      (tester) async {
        await saveSlots(2);
        final menu = _SaveMenu();
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.$1;
        try {
          await menu.ready(pump: () => tester.pump());
          final source = engine.console;
          final choices = List.of(source.actions);
          final paint = _paint(source), revision = source.revision.value;
          final pending = source.nextKeyEvent;
          final baseline = _withoutEntityMetadata(source);
          Future<void> render(Console console) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildModernTheme(),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: layout.$1,
                    textScaler: TextScaler.linear(layout.$2),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: DirectContent(console: console, onAction: (_) {}),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          Map<String, Object?> signature() => {
            'text': tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data ?? t.textSpan!.toPlainText())
                .toList(),
            'controls': [
              for (final action in choices)
                (() {
                  final target = find.byKey(
                    ValueKey(
                      'direct-action:${action.y}:${action.x}:${action.key}',
                    ),
                  );
                  final data = tester.getSemantics(target).getSemanticsData();
                  return (
                    action.key,
                    tester.getRect(target),
                    data.label,
                    data.value,
                    data.hint,
                    data.flagsCollection.toString(),
                    data.hasAction(SemanticsAction.tap),
                  );
                })(),
            ],
          };
          await render(baseline);
          final before = signature();
          await render(source);
          expect(signature(), before);
          for (final save in source.actions.where(
            (a) => a.entityType == 'save',
          )) {
            expect(save.entityLabel, isNotNull);
            expect(find.text(save.entityLabel!), findsNothing);
          }
          expect(_paint(source), paint);
          expect(source.revision.value, revision);
          expect(source.actions, orderedEquals(choices));
          expect(identical(source.nextKeyEvent, pending), true);
          expect(source.lastKey, isNull);
        } finally {
          await menu.stop(pump: () => tester.pump());
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          semantics.dispose();
        }
      },
    );
  }
}
