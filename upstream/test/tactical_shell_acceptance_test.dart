import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/help_system.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

const _captureKey = ValueKey('tactical-shell-acceptance-capture');
bool _artworkWarmed = false;
Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _grid => _key('tactical-map-grid');

/// A prepared saved campaign with explicitly synthetic map geometry/actions.
/// The shell, engine key readers, help report and refusal prompt are production
/// code. This fixture does not claim to run the private siteMode turn loop.
void _publishOperation() {
  engine.console.screen = 'tactical';
  engine.console.actions.clear();
  siteMovementOptions(canMove: true);
  for (final (key, label, enabled, row, column) in [
    ('g', 'Get loot', currentTile.loot, 23, 1),
    ('m', 'View full map', true, 23, 12),
    ('e', 'Equip squad', true, 23, 24),
    ('u', 'Use / interact', currentTile.special != TileSpecial.none, 24, 1),
    ('v', 'Flee', false, 24, 12),
    ('?', 'Operation help', true, 24, 24),
  ]) {
    engine.move(row, column);
    engine.console.addAction(key, label, enabled: enabled);
  }
  engine.move(0, 0);
}

class _SourceReader {
  _SourceReader(WidgetTester tester) : source = engine.console {
    result = engine.getKey().then((key) {
      completed = true;
      return key;
    });
    addTearDown(() async {
      if (!completed) {
        source.sendInput('Enter');
        await tester.pump();
      }
      expect(
        completed,
        isTrue,
        reason: 'Drain the original reader without awaiting fake-async work.',
      );
    });
  }

  final Console source;
  late final Future<int> result;
  bool completed = false;
}

String _state() => jsonEncode({
  'campaign': game.gameState.toJson(),
  'position': [game.locx, game.locy, game.locz],
  'tiles': [
    for (final tile in levelMap.all)
      [tile.flag, tile.siegeflag, tile.inLOS, tile.special.name],
  ],
});

String _textWithin(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join(' ');

TacticalMapPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_grid).painter! as TacticalMapPainter;

Offset _tileCenter(WidgetTester tester, int x, int y) {
  final painter = _painter(tester);
  final box = tester.renderObject<RenderBox>(_grid);
  final cellSize = box.size.width / painter.snapshot.columnCount;
  return box.localToGlobal(
    Offset(
      (x - painter.snapshot.xStart + .5) * cellSize,
      (y - painter.snapshot.yStart + .5) * cellSize,
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final directory = await Directory(
      '../reports/tactical-acceptance/shell',
    ).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/synthetic-qa-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Flush both Flutter ImageProviders and the production portrait/icon painters'
/// own decoding futures before accepting screenshots as visual evidence.
Future<void> _settleArtwork(WidgetTester tester) async {
  // Every case uses the same saved squad and image providers. Reusing the
  // warmed production caches avoids awaiting a previous test's fake-async
  // decoding futures from a new runAsync zone.
  if (_artworkWarmed) {
    await tester.pumpAndSettle();
    return;
  }
  final context = tester.element(_grid);
  final providers = <ImageProvider>[
    const AssetImage(JournalPalette.paperAsset),
    const AssetImage(JournalPalette.leatherAsset),
    for (final atlas in [
      tacticalTerrainAtlas,
      tacticalObjectAtlas,
      tacticalExtraObjectAtlas,
      tacticalHazardAtlas,
    ])
      AssetImage(atlas.asset),
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      image.image,
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      if (box.decoration case BoxDecoration(image: final decoration?))
        decoration.image,
  ];
  final portraitFutures = tester
      .widgetList<FutureBuilder<List<ui.Image?>>>(
        find.byWidgetPredicate(
          (widget) => widget is FutureBuilder<List<ui.Image?>>,
        ),
      )
      .map((widget) => widget.future)
      .whereType<Future<List<ui.Image?>>>()
      .toList();
  final iconFutures = tester
      .widgetList<FutureBuilder<ui.Image?>>(
        find.byWidgetPredicate((widget) => widget is FutureBuilder<ui.Image?>),
      )
      .map((widget) => widget.future)
      .whereType<Future<ui.Image?>>()
      .toList();
  await tester.runAsync(() async {
    await Future.wait([
      for (final provider in providers) precacheImage(provider, context),
      for (final future in portraitFutures)
        future.then((images) {
          expect(
            images.first,
            isNotNull,
            reason: 'Portrait art must be decoded.',
          );
        }),
      for (final future in iconFutures)
        future.then((image) {
          expect(image, isNotNull, reason: 'Journal icon art must be decoded.');
        }),
    ]);
  });
  await tester.pumpAndSettle();
  _artworkWarmed = true;
}

void main() {
  late String fixture;
  final scenarios =
      <({String name, Future<void> Function(WidgetTester) run})>[];
  void acceptanceCase(String name, Future<void> Function(WidgetTester) run) =>
      scenarios.add((name: name, run: run));
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([serif.load(), sans.load(), icons.load()]);
  });

  void prepareFixture() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.site;
    game.activeSite = game.squad.first.site;
    game.activeSite!
      ..type = SiteType.amRadioStation
      ..name = 'SYNTHETIC QA · Radio station'
      ..frontName = null;
    game.siteAlarm = false;
    game.siteAlarmTimer = -1;
    game.postAlarmTimer = 0;
    game.encounter.clear();
    game.groundLoot.clear();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    for (var y = 8; y <= 14; y++) {
      for (var x = 29; x <= 42; x++) {
        levelMap[x][y][0]
          ..known = true
          ..inLOS = true
          ..wall = y == 8 || y == 14 || x == 29 || x == 42;
      }
    }
    levelMap[29][11][0]
      ..wall = false
      ..exit = true;
    levelMap[36][11][0]
      ..door = true
      ..locked = true
      ..knownLock = true;
    levelMap[36][10][0].wall = true;
    levelMap[36][12][0].wall = true;
    levelMap[34][10][0].special = TileSpecial.radioBroadcastStudio;
    levelMap[33][11][0].special = TileSpecial.computer;
    levelMap[34][12][0].special = TileSpecial.ceoSafe;
    levelMap[37][10][0].special = TileSpecial.corporateFiles;
    levelMap[37][12][0].loot = true;
    levelMap[32][10][0].special = TileSpecial.stairsUp;
    levelMap[38][12][0].debris = true;
    levelMap[39][12][0].fireStart = true;
    levelMap[43][11][0]
      ..special = TileSpecial.bankVault
      ..siegeHeavyUnit = true;
    engine.console = Console();
    journalReadingScale.value = 1;
    _publishOperation();
  }

  Future<void> mount(WidgetTester tester, Size size, double scale) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    journalReadingScale.value = scale;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view
        ..resetDevicePixelRatio()
        ..resetPhysicalSize();
      journalReadingScale.value = 1;
    });
    await tester.pumpWidget(
      const RepaintBoundary(key: _captureKey, child: MainApp()),
    );
    await tester.pumpAndSettle();
    await _settleArtwork(tester);
    final art = _painter(tester).art;
    expect(art, isNotNull, reason: 'Shell evidence must use decoded artwork.');
    expect(art!.terrain.width, greaterThan(0));
    expect(art.objects.width, greaterThan(0));
    expect(art.hazards.width, greaterThan(0));
    final portraits = find.byType(CrewPortrait);
    expect(portraits, findsWidgets);
    for (var index = 0; index < portraits.evaluate().length; index++) {
      expect(
        find.descendant(
          of: portraits.at(index),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
        reason: 'Every displayed crew portrait must paint decoded artwork.',
      );
    }
    expect(find.textContaining('SYNTHETIC QA'), findsWidgets);
    final inspector = _key('tactical-tile-inspector');
    final inspectorRect = tester.getRect(inspector);
    final leftPane = tester.getRect(_key('tactical-field-plan'));
    expect(inspectorRect.left, greaterThanOrEqualTo(leftPane.left));
    expect(inspectorRect.right, lessThanOrEqualTo(leftPane.right));
    expect(inspectorRect.top, greaterThanOrEqualTo(leftPane.top));
    expect(inspectorRect.bottom, lessThanOrEqualTo(leftPane.bottom));
    expect(inspectorRect.top, greaterThanOrEqualTo(0));
    expect(inspectorRect.bottom, lessThanOrEqualTo(size.height));
    expect(
      inspectorRect.top - tester.getRect(_key('tactical-map-viewport')).bottom,
      inInclusiveRange(0, 8),
      reason: 'The current-tile inspector must stay pinned beneath the map.',
    );
    expect(
      find
          .descendant(
            of: inspector,
            matching: find.textContaining('Current tile · '),
          )
          .hitTestable(),
      findsOneWidget,
      reason:
          'Current location must be readable before scrolling or inspecting.',
    );
    expect(
      find
          .descendant(
            of: inspector,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  (widget.data?.startsWith('Press ') == true ||
                      widget.data?.startsWith('Move one outlined tile') ==
                          true),
            ),
          )
          .hitTestable(),
      findsOneWidget,
      reason: 'The current action hint must be visible on the initial frame.',
    );
    expect(tester.takeException(), isNull);
  }

  Future<void> modalKeys(WidgetTester tester) async {
    final keyboard = FocusManager.instance.rootScope.descendants.singleWhere(
      (node) => node.debugLabel == 'Game keyboard',
    );
    keyboard.requestFocus();
    await tester.pump();
    expect(
      ModalRoute.of(keyboard.context!)?.isCurrent,
      isFalse,
      reason:
          'The operation route must be covered by the presentation overlay.',
    );
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) => widget is Focus && identical(widget.focusNode, keyboard),
      ),
    );
    // Also exercise the real handler directly: some platforms refuse focus on
    // a covered route, whereas browser focus can still deliver a stale event.
    expect(
      focus.onKeyEvent!(
        keyboard,
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyF,
          physicalKey: PhysicalKeyboardKey.keyF,
          character: 'f',
          timeStamp: Duration.zero,
        ),
      ),
      KeyEventResult.ignored,
      reason: 'Stale background focus must not start combat behind an overlay.',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU, character: 'u');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG, character: 'g');
    await tester.pumpAndSettle();
  }

  for (final (size, scale) in [
    (const Size(1280, 800), 1.0),
    (const Size(800, 600), 1.5),
  ]) {
    final suffix = '${size.width.toInt()}-${(scale * 100).round()}pct';

    acceptanceCase('real tactical shell keeps map dialogs passive at $suffix', (
      tester,
    ) async {
      final reader = _SourceReader(tester);
      final pending = engine.console.nextKeyEvent;
      final actions = List<ConsoleAction>.of(engine.console.actions);
      final before = _state();
      reseedRNG(seed: 829314);
      final rolls = List.generate(20, (_) => lcsRandom(100000));
      reseedRNG(seed: 829314);
      await mount(tester, size, scale);

      final grid = tester.renderObject<RenderBox>(_grid);
      final cellStart = grid.localToGlobal(Offset.zero);
      final cellEnd = grid.localToGlobal(Offset(grid.size.width / 23, 0));
      expect(
        (cellEnd - cellStart).distance,
        greaterThanOrEqualTo(31.99),
        reason: 'Default camera must retain readable 32px tactical cells.',
      );
      final squad = _tileCenter(tester, 35, 11);
      expect(
        tester.getRect(_key('tactical-map-viewport')).contains(squad),
        isTrue,
      );
      expect((Offset.zero & size).contains(squad), isTrue);
      await _capture(tester, 'shell-$suffix');

      await tester.ensureVisible(_key('field-plan-key-open'));
      await tester.tap(_key('field-plan-key-open'));
      await tester.pumpAndSettle();
      expect(_key('field-plan-key-dialog'), findsOneWidget);
      await modalKeys(tester);
      expect(_key('field-plan-key-dialog'), findsOneWidget);
      expect(reader.completed, isFalse);
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.nextKeyEvent, same(pending));
      expect(engine.console.actions, orderedEquals(actions));
      expect(_state(), before);
      await _capture(tester, 'map-key-$suffix');
      await tester.tap(_key('field-plan-key-close'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_key('tactical-tile-details'));
      await tester.tap(_key('tactical-tile-details'));
      await tester.pumpAndSettle();
      expect(find.text('Close tile details'), findsOneWidget);
      await modalKeys(tester);
      expect(find.text('Close tile details'), findsOneWidget);
      expect(reader.completed, isFalse);
      expect(engine.console.nextKeyEvent, same(pending));
      expect(engine.console.actions, orderedEquals(actions));
      expect(_state(), before);
      await _capture(tester, 'tile-details-$suffix');
      await tester.tap(find.text('Close tile details'));
      await tester.pumpAndSettle();

      final mapControls = find.byTooltip('Map controls');
      if (mapControls.evaluate().isNotEmpty) {
        await tester.tap(mapControls);
        await tester.pumpAndSettle();
        final centerChoice = find.text('Center squad at readable size');
        expect(centerChoice, findsOneWidget);
        await modalKeys(tester);
        expect(centerChoice, findsOneWidget);
        expect(reader.completed, isFalse);
        expect(engine.console.awaitingInput, isTrue);
        expect(engine.console.nextKeyEvent, same(pending));
        expect(engine.console.actions, orderedEquals(actions));
        expect(_state(), before);
        await tester.tap(centerChoice);
        await tester.pumpAndSettle();
        expect(centerChoice, findsNothing);
      }

      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.lastKey, isNull);
      expect(engine.console.actions, orderedEquals(actions));
      expect(_state(), before);
      expect(List.generate(20, (_) => lcsRandom(100000)), rolls);
      engine.console.sendInput('Enter');
      await tester.pump();
      expect(reader.completed, isTrue);
      expect(await reader.result, engine.Key.enter);
      expect(tester.takeException(), isNull);
    });

    acceptanceCase(
      'source Operation help explains the complete field flow at $suffix',
      (tester) async {
        final reader = _SourceReader(tester);
        await mount(tester, size, scale);
        final before = _state();
        reseedRNG(seed: 973251);
        final rolls = List.generate(20, (_) => lcsRandom(100000));
        reseedRNG(seed: 973251);
        await tester.ensureVisible(find.text('Operation help'));
        await tester.tap(find.text('Operation help'));
        await tester.pump();
        expect(reader.completed, isTrue);
        expect(await reader.result, '?'.codeUnitAt(0));
        var helpComplete = false;
        final help = helpOnSitemode().whenComplete(() => helpComplete = true);
        addTearDown(() async {
          if (!helpComplete) {
            engine.console.sendInput('Enter');
            await tester.pump();
          }
          expect(helpComplete, isTrue);
        });
        await tester.pumpAndSettle();
        final report = engine.console.eventMessage!.replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        for (final instruction in [
          'Move one tile with arrow keys',
          'door tries to open it',
          'squad stays outside until it opens',
          'Use / interact (U)',
          'Get loot (G)',
          'View full map (M) only inspects',
          'Flee escapes an encounter',
          'walking onto an Exit tile leaves the site',
        ]) {
          expect(report, contains(instruction));
        }
        expect(find.text('Field guide'), findsWidgets);
        final announcement = _key('journal-current-announcement');
        expect(announcement, findsOneWidget);
        await _capture(tester, 'operation-help-$suffix');
        final scroll = tester.state<ScrollableState>(
          find
              .ancestor(of: announcement, matching: find.byType(Scrollable))
              .first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, scroll.position.maxScrollExtent);
        expect(find.text('Continue').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        expect(helpComplete, isTrue);
        await help;
        expect(_state(), before);
        expect(List.generate(20, (_) => lcsRandom(100000)), rolls);

        _publishOperation();
        final resumed = _SourceReader(tester);
        engine.refresh();
        await tester.pumpAndSettle();
        expect(_grid, findsOneWidget);
        expect(engine.console.awaitingInput, isTrue);
        engine.console.sendInput('Enter');
        await tester.pump();
        expect(resumed.completed, isTrue);
        await resumed.result;
      },
    );

    for (final (name, special, loot, label, guidance, actionKey) in [
      (
        'stairs',
        TileSpecial.stairsUp,
        false,
        'Stairs up',
        'Press U to go upstairs.',
        'u',
      ),
      ('loot', TileSpecial.none, true, 'Loot', 'Press G to get loot.', 'g'),
      (
        'safe',
        TileSpecial.ceoSafe,
        false,
        'Safe',
        'Press U to use / interact.',
        'u',
      ),
    ]) {
      acceptanceCase(
        'current squad on $name has actionable guidance at $suffix',
        (tester) async {
          currentTile
            ..special = special
            ..loot = loot;
          _publishOperation();
          final reader = _SourceReader(tester);
          final before = _state();
          await mount(tester, size, scale);
          final inspector = _key('tactical-tile-inspector');
          final text = _textWithin(tester, inspector);
          expect(text, contains('Current tile · $label'));
          expect(text, contains(guidance));
          expect(text, isNot(contains('Stand here')));
          expect(
            find
                .descendant(
                  of: inspector,
                  matching: find.textContaining(guidance),
                )
                .hitTestable(),
            findsOneWidget,
            reason: 'Current U/G guidance must be readable without scrolling.',
          );
          expect(
            engine.console.actions
                .singleWhere((action) => action.key == actionKey)
                .enabled,
            isTrue,
          );
          await tester.ensureVisible(_key('tactical-tile-details'));
          await tester.tap(_key('tactical-tile-details'));
          await tester.pumpAndSettle();
          expect(
            _textWithin(tester, find.byType(AlertDialog)).toLowerCase(),
            contains(guidance.toLowerCase()),
          );
          await _capture(tester, 'current-$name-details-$suffix');
          await tester.tap(find.text('Close tile details'));
          await tester.pumpAndSettle();
          expect(reader.completed, isFalse);
          expect(_state(), before);
          expect(tester.takeException(), isNull);
          engine.console.sendInput('Enter');
          await tester.pump();
          expect(reader.completed, isTrue);
        },
      );
    }

    acceptanceCase(
      'staged source door refusal leaves the squad outside at $suffix',
      (tester) async {
        final reader = _SourceReader(tester);
        await mount(tester, size, scale);
        final before = _state();
        await tester.tapAt(_tileCenter(tester, 36, 11));
        await tester.pump();
        expect(reader.completed, isTrue);
        expect(await reader.result, engine.Key.rightArrow);
        expect((game.locx, game.locy), (35, 11));

        // The private engine door handler owns movement/lock resolution. Stage
        // its production refusal prompt after the shell's real direction reader;
        // declining must never make the presentation move the squad or open it.
        var decisionComplete = false;
        final decision = sitemodePrompt(
          'You try the door, but it is locked.',
          'Try to pick the lock? (Yes or No)',
        ).whenComplete(() => decisionComplete = true);
        addTearDown(() async {
          if (!decisionComplete) {
            engine.console.sendInput('n');
            await tester.pump();
          }
          expect(decisionComplete, isTrue);
        });
        await tester.pumpAndSettle();
        final pending = engine.console.nextKeyEvent;
        expect(find.text('No').hitTestable(), findsOneWidget);
        await tester.tapAt(_tileCenter(tester, 36, 11));
        await tester.pump();
        expect(engine.console.nextKeyEvent, same(pending));
        expect(engine.console.awaitingInput, isTrue);
        expect((game.locx, game.locy), (35, 11));
        await _capture(tester, 'staged-door-refusal-$suffix');
        await tester.tap(find.text('No'));
        await tester.pump();
        expect(decisionComplete, isTrue);
        expect(await decision, isFalse);
        expect(levelMap[36][11][0].door, isTrue);
        expect(_state(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // The production portrait cache owns decoded-image futures for the lifetime
  // of the application. Keep all acceptance scenarios in one test event loop,
  // just as a running app does, rather than carrying those futures between
  // unrelated fake-async zones and mistaking pending thumbnails for real art.
  testWidgets(
    'tactical shell acceptance with decoded art at desktop and 150% compact size',
    (tester) async {
      for (final scenario in scenarios) {
        await tester.pumpWidget(const SizedBox.shrink());
        prepareFixture();
        debugPrintSynchronously('Acceptance scenario: ${scenario.name}');
        await scenario.run(tester);
        expect(tester.takeException(), isNull);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
