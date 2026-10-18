import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';

import 'test_support.dart';

/// These tests run the original siteMode input loop, including its U dispatch
/// to useTileSpecial and its complete G branch (lootGround, item transfer and
/// tile clearing). The saved campaign's skills, equipment and RNG are intact.
/// A declared flat map is installed at a paused input boundary; this is action
/// acceptance on synthetic geometry, not a normal-navigation playthrough.
class _StoppedFixture implements Exception {
  const _StoppedFixture();
}

class _OriginalFieldFlow {
  _OriginalFieldFlow() : console = engine.console {
    completed = siteMode(game.activeSite!).then<void>(
      (_) => finished = true,
      onError: (Object error, StackTrace stack) {
        finished = true;
        if (error is! _StoppedFixture) {
          failure = error;
          failureStack = stack;
        }
      },
    );
    unawaited(completed);
  }

  final Console console;
  late final Future<void> completed;
  final List<String> reports = [];
  bool finished = false;
  Object? failure;
  StackTrace? failureStack;

  void check() {
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> stop(WidgetTester tester) async {
    // Cancel only after gameplay assertions. This unwinds the outstanding
    // source input reader and does not simulate escape or a campaign outcome.
    for (var attempt = 0; attempt < 30 && !finished; attempt++) {
      final pending = console.nextKeyEvent;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const _StoppedFixture());
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finished, isTrue, reason: 'The fixture reader must be released.');
    await tester.pump();
  }
}

ConsoleAction _sourceAction(String key) =>
    engine.console.actions.singleWhere((action) => action.key == key);

String _inspectorText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('tactical-tile-inspector')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join(' ');

TacticalMapCell _currentCell() => TacticalMapSnapshot.capture().cells
    .singleWhere((cell) => cell.kind == TacticalTileKind.squad);

Future<void> _clickSourceAction(WidgetTester tester, String key) async {
  final action = _sourceAction(key);
  expect(action.enabled, isTrue, reason: 'Source action $key must be enabled.');
  final direct = find.byKey(
    ValueKey('direct-action:${action.y}:${action.x}:${action.key}'),
  );
  final finder = direct.evaluate().isNotEmpty
      ? direct
      : find.text(action.label, findRichText: true).first;
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  await tester.tap(finder);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _waitForField(
  WidgetTester tester,
  _OriginalFieldFlow flow, {
  int afterRevision = -1,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    flow.check();
    expect(flow.finished, isFalse);
    final console = flow.console;
    if (console.awaitingInput &&
        console.screen == 'tactical' &&
        console.revision.value > afterRevision) {
      expect(find.byType(TacticalMapView), findsOneWidget);
      return;
    }
    if (console.awaitingInput && console.eventMessage != null) {
      // Acknowledge only real source reports. No skill result or random
      // encounter is replaced by an invented result or scripted answer.
      flow.reports.add(console.eventMessage!);
      final continuation = find.text('Continue');
      expect(continuation, findsWidgets);
      await tester.ensureVisible(continuation.first);
      await tester.tap(continuation.first);
    } else {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }
  fail('The original field reader did not return: ${flow.console.screen}.');
}

void _installSyntheticMap() {
  game.locx = 35;
  game.locy = 11;
  game.locz = 0;
  levelMap = List.generate(
    MAPX,
    (x) => List.generate(
      MAPY,
      (y) => List.generate(
        MAPZ,
        (z) => SiteTile(x, y, z)
          ..known = true
          ..inLOS = true,
      ),
    ),
  );
}

Future<void> _redrawField(WidgetTester tester, _OriginalFieldFlow flow) async {
  final revision = flow.console.revision.value;
  // Enter has no gameplay branch in the field loop. It lets the original
  // source repaint actions from the newly prepared map, rather than forging U
  // or G action metadata in the test.
  expect(flow.console.sendInput('Enter'), isTrue);
  await _waitForField(tester, flow, afterRevision: revision);
}

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.site;
    game.activeSite = game.sites.firstWhere(
      (site) => site.type == SiteType.amRadioStation,
    );
    game.activeSquadMember = null;
    game.sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)
      ..loc = game.activeSite;
    engine.console = Console();
    journalReadingScale.value = 1;
  });

  Future<_OriginalFieldFlow> mount(
    WidgetTester tester,
    void Function() prepareMap,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1100);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final flow = _OriginalFieldFlow();
    addTearDown(() async {
      await flow.stop(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      journalReadingScale.value = 1;
    });
    await tester.pumpWidget(const MainApp());
    await _waitForField(tester, flow);
    _installSyntheticMap();
    prepareMap();
    await _redrawField(tester, flow);
    expect(tester.takeException(), isNull);
    return flow;
  }

  testWidgets('original U uses stairs and the next field view shows level 2', (
    tester,
  ) async {
    final flow = await mount(tester, () {
      levelMap[35][11][0].special = TileSpecial.stairsUp;
      levelMap[35][11][1].special = TileSpecial.stairsDown;
    });
    expect(game.locz, 0);
    expect(_currentCell().underlyingKind, TacticalTileKind.stairsUp);
    expect(_sourceAction('u').enabled, isTrue);
    expect(_inspectorText(tester), contains('Press U to go upstairs'));
    final revision = flow.console.revision.value;
    await _clickSourceAction(tester, 'u');
    await _waitForField(tester, flow, afterRevision: revision);

    expect(game.locz, 1, reason: 'useTileSpecial must change the real floor.');
    expect((game.locx, game.locy), (35, 11));
    expect(find.text('LEVEL 2'), findsOneWidget);
    expect(_currentCell().underlyingKind, TacticalTileKind.stairsDown);
    expect(_currentCell().featureLabel, 'Stairs down');
    expect(_inspectorText(tester), contains('Press U to go downstairs'));
    expect(TacticalMapSnapshot.capture().currentDescription, 'Stairs down');
    expect(levelMap[35][11][0].special, TileSpecial.stairsUp);
    expect(_sourceAction('u').enabled, isTrue);
    flow.check();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets(
    'original G collects map and dropped loot and clears the marker',
    (tester) async {
      final existingLoot = Loot(LootTypeIds.microphone);
      final flow = await mount(tester, () {
        currentTile.loot = true;
        game.groundLoot.add(existingLoot);
      });
      final beforeCount = game.activeSquad!.loot.length;
      expect(_currentCell().lootAvailable, isTrue);
      expect(_currentCell().actionHint, contains('press G'));
      expect(_inspectorText(tester), contains('Press G'));
      expect(
        TacticalMapSnapshot.capture().currentDescription,
        contains('Loot'),
      );
      expect(_sourceAction('g').enabled, isTrue);
      final revision = flow.console.revision.value;
      await _clickSourceAction(tester, 'g');
      await _waitForField(tester, flow, afterRevision: revision);

      expect(currentTile.loot, isFalse);
      expect(game.groundLoot, isEmpty);
      expect(
        game.activeSquad!.loot.any((item) => identical(item, existingLoot)),
        isTrue,
        reason: 'The actual dropped item must be retained by the squad.',
      );
      expect(
        game.activeSquad!.loot.length,
        greaterThanOrEqualTo(beforeCount + 2),
        reason: 'lootGroundSite also generates a real station item.',
      );
      expect(flow.reports.join('\n'), contains('You find:'));
      expect(_currentCell().lootAvailable, isFalse);
      expect(_currentCell().objectSprite, isNull);
      expect(TacticalMapSnapshot.capture().currentDescription, 'Open floor');
      expect(_sourceAction('g').enabled, isFalse);
      expect(_inspectorText(tester), isNot(contains('Press G')));
      flow.check();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  testWidgets(
    'real safe refusal returns to field and entry fixtures disable U',
    (tester) async {
      final flow = await mount(tester, () {
        currentTile.special = TileSpecial.ceoSafe;
      });
      expect(_currentCell().featureLabel, 'Safe');
      expect(_inspectorText(tester), contains('Press U to use / interact'));
      expect(_sourceAction('u').enabled, isTrue);
      final sourceConsole = flow.console;
      final beforeCampaign = jsonEncode(game.gameState.toJson());
      final beforeFlags = currentTile.flag;
      final beforeActions = flow.console.actions
          .map((action) => action.key)
          .toSet();
      final revision = flow.console.revision.value;
      await _clickSourceAction(tester, 'u');

      expect(flow.console.awaitingInput, isTrue);
      expect(
        flow.console.actions.map((action) => action.key),
        containsAll(['y', 'n']),
      );
      expect(
        flow.console.buffer
            .map((row) => row.map((cell) => cell.glyph).join())
            .join('\n'),
        contains('Crack it?'),
      );
      await _clickSourceAction(tester, 'n');
      await _waitForField(tester, flow, afterRevision: revision);

      expect(engine.console, same(sourceConsole));
      expect(flow.console.awaitingInput, isTrue);
      expect(flow.console.screen, 'tactical');
      expect(currentTile.special, TileSpecial.ceoSafe);
      expect(currentTile.flag, beforeFlags);
      expect((game.locx, game.locy, game.locz), (35, 11, 0));
      expect(jsonEncode(game.gameState.toJson()), beforeCampaign);
      expect(
        flow.console.actions.map((action) => action.key).toSet(),
        beforeActions,
      );
      expect(_inspectorText(tester), contains('Current tile · Safe'));
      expect(_sourceAction('u').enabled, isTrue);

      // Additional prepared fixtures exercise the source menu predicate. These
      // passive entry events must never offer the safe's manual-use command.
      for (final special in [TileSpecial.computer, TileSpecial.table]) {
        currentTile.special = special;
        await _redrawField(tester, flow);
        expect(_sourceAction('u').enabled, isFalse, reason: special.name);
        expect(_currentCell().actionHint, contains('on entry'));
        expect(_currentCell().actionHint, isNot(contains('press U')));
      }
      flow.check();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
