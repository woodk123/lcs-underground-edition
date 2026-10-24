import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

TacticalMapCell _cellAt(TacticalMapSnapshot snapshot, int x, int y) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

Finder get _grid => find.byKey(const ValueKey('tactical-map-grid'));
Finder get _inspector => find.byKey(const ValueKey('tactical-tile-inspector'));

Offset _tileCenter(WidgetTester tester, int x, int y) {
  final snapshot = TacticalMapSnapshot.capture();
  final box = tester.renderObject<RenderBox>(_grid);
  final cellSize = box.size.width / snapshot.columnCount;
  return box.localToGlobal(
    Offset(
      (x - snapshot.xStart + .5) * cellSize,
      (y - snapshot.yStart + .5) * cellSize,
    ),
  );
}

String _inspectorText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: _inspector, matching: find.byType(Text)),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join(' ');

String _state() => jsonEncode({
  'game': game.gameState.toJson(),
  'position': [game.locx, game.locy, game.locz],
  'tiles': [
    for (final tile in levelMap.all)
      [tile.flag, tile.siegeflag, tile.inLOS, tile.special.name],
  ],
});

void main() {
  setUpAll(ensureGameDataLoaded);

  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    game.activeSite = Site(SiteType.amRadioStation)
      ..name = 'A known radio station';
    game.siteAlarmTimer = -1;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    for (final (x, y) in [(35, 11), (36, 11), (37, 11), (35, 10), (35, 12)]) {
      levelMap[x][y][0]
        ..known = true
        ..inLOS = true;
    }
    levelMap[35][10][0].wall = true;
    levelMap[35][12][0].door = true;
    levelMap[37][11][0].special = TileSpecial.radioBroadcastStudio;
    levelMap[34][11][0]
      ..wall = true
      ..door = true
      ..loot = true
      ..grass = true
      ..outdoor = true
      ..firePeak = true
      ..restricted = true
      ..inLOS = true
      ..siegeHeavyUnit = true
      ..special = TileSpecial.bankVault;
  });

  Future<void> mount(
    WidgetTester tester,
    List<String> moves, {
    bool movementEnabled = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TacticalMapView(
              onMove: moves.add,
              movementEnabled: movementEnabled,
              showHeading: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, int x, int y) async {
    await tester.tapAt(_tileCenter(tester, x, y));
    await tester.pumpAndSettle();
  }

  test(
    'artwork metadata describes the site and known room without leaking fog',
    () {
      levelMap[36][11][0].firePeak = true;
      final snapshot = TacticalMapSnapshot.capture();
      expect(snapshot.siteType, SiteType.amRadioStation.name);
      expect(_cellAt(snapshot, 37, 11).objectSprite, isNotNull);
      expect(_cellAt(snapshot, 36, 11).hazardSprite, isNotNull);

      final hidden = _cellAt(snapshot, 34, 11);
      final emptyFog = _cellAt(snapshot, 33, 11);
      for (final cell in [hidden, emptyFog]) {
        expect(cell.kind, TacticalTileKind.unknown);
        expect(cell.label, 'Unexplored');
        expect(cell.objectSprite, isNull);
        expect(cell.hazardSprite, isNull);
        expect(cell.groundSprite, isNull);
        expect(cell.icon, isNull);
        expect(cell.visible, isFalse);
        expect(cell.burning, isFalse);
        expect(cell.restricted, isFalse);
        expect(cell.horizontalDoor, isFalse);
      }
      expect(levelMap[34][11][0].known, isFalse);
      expect(levelMap[34][11][0].inLOS, isTrue);
    },
  );

  testWidgets(
    'hover inspects known and hidden tiles without issuing movement',
    (tester) async {
      final moves = <String>[];
      await mount(tester, moves);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(_tileCenter(tester, 37, 11));
      await tester.pumpAndSettle();
      expect(_inspector, findsOneWidget);
      expect(_inspectorText(tester), contains('Radio studio'));

      await mouse.moveTo(_tileCenter(tester, 34, 11));
      await tester.pumpAndSettle();
      expect(_inspectorText(tester), contains('Unexplored'));
      expect(_inspectorText(tester), isNot(contains('vault')));
      expect(_inspectorText(tester), isNot(contains('Armored')));
      expect(_inspectorText(tester), isNot(contains('Fire')));
      expect(moves, isEmpty);
    },
  );

  testWidgets('wall, distant room and unknown clicks inspect without moving', (
    tester,
  ) async {
    final moves = <String>[];
    await mount(tester, moves);
    for (final (x, y, label) in [
      (35, 10, 'Wall'),
      (37, 11, 'Radio studio'),
      (34, 11, 'Unexplored'),
    ]) {
      await tapTile(tester, x, y);
      expect(_inspectorText(tester), contains(label));
      expect(moves, isEmpty);
    }
    expect(_inspectorText(tester), isNot(contains('vault')));
    expect(levelMap[34][11][0].known, isFalse);
  });

  testWidgets(
    'adjacent floor and door clicks retain engine direction commands',
    (tester) async {
      final moves = <String>[];
      await mount(tester, moves);
      await tapTile(tester, 36, 11);
      await tapTile(tester, 35, 12);
      expect(moves, ['Right', 'Down']);
      expect((game.locx, game.locy, game.locz), (35, 11, 0));
      expect(levelMap[35][12][0].door, isTrue);
      expect(tester.getSize(_grid).aspectRatio, closeTo(23 / 10, .0001));
    },
  );

  for (final compact in [false, true]) {
    testWidgets(
      'legacy wall terminal inspection and revisit (compact=$compact)',
      (tester) async {
        levelMap[35][10][0].special = TileSpecial.insuranceClaimsTerminal;
        final before = _state();
        final moves = <String>[];
        await mount(tester, moves);
        if (compact) {
          tester.view.physicalSize = const Size(1024, 720);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildJournalTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TacticalMapView(onMove: moves.add),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        for (var visit = 0; visit < 2; visit++) {
          await tapTile(tester, 35, 10);
          final text = _inspectorText(tester);
          expect(text, contains('Solid wall. You cannot move onto this tile.'));
          expect(text, isNot(contains('reach this tile')));
          expect(text, isNot(contains('press U')));
          expect(
            _cellAt(TacticalMapSnapshot.capture(), 35, 10).objectSprite,
            isNull,
          );
          await tapTile(tester, 37, 11);
          expect(_inspectorText(tester), contains('Radio studio'));
        }
        expect(moves, isEmpty);
        expect(_state(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('artwork, hover and inspection preserve campaign state and RNG', (
    tester,
  ) async {
    final before = _state();
    reseedRNG(seed: 719125);
    final expectedRolls = List.generate(20, (_) => lcsRandom(100000));
    reseedRNG(seed: 719125);
    final moves = <String>[];
    await mount(tester, moves);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final (x, y) in [(37, 11), (34, 11), (35, 10)]) {
      await mouse.moveTo(_tileCenter(tester, x, y));
      await tester.pumpAndSettle();
      await tapTile(tester, x, y);
    }
    expect(moves, isEmpty);
    expect(_state(), before);
    expect(List.generate(20, (_) => lcsRandom(100000)), expectedRolls);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'blocked movement keeps inspection but disables every move callback',
    (tester) async {
      final moves = <String>[];
      await mount(tester, moves, movementEnabled: false);
      await tapTile(tester, 36, 11);
      await tapTile(tester, 37, 11);
      expect(_inspectorText(tester), contains('Radio studio'));
      expect(moves, isEmpty);

      final painter =
          tester.widget<CustomPaint>(_grid).painter! as TacticalMapPainter;
      expect(painter.onMove, isNull);
      final semantics = painter.semanticsBuilder(tester.getSize(_grid));
      for (final tile in semantics) {
        expect(tile.properties.onTap, isNull);
        expect(tile.properties.button, isNot(isTrue));
      }
      for (final direction in ['up', 'down', 'left', 'right']) {
        final button = tester.widget<IconButton>(
          find.byKey(ValueKey('tactical-move:$direction')),
        );
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long press inspects adjacent fire and doors without moving', (
    tester,
  ) async {
    levelMap[36][11][0].firePeak = true;
    final moves = <String>[];
    await mount(tester, moves);
    for (final (x, y) in [(36, 11), (35, 12)]) {
      await tester.longPressAt(_tileCenter(tester, x, y));
      await tester.pumpAndSettle();
      final painter =
          tester.widget<CustomPaint>(_grid).painter! as TacticalMapPainter;
      expect((painter.inspected?.x, painter.inspected?.y), (x, y));
      expect(moves, isEmpty);
      expect(find.text('Close tile details'), findsOneWidget);
      await tester.tap(find.text('Close tile details'));
      await tester.pumpAndSettle();
    }
    expect(levelMap[36][11][0].firePeak, isTrue);
    expect(levelMap[35][12][0].door, isTrue);
    expect((game.locx, game.locy), (35, 11));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inspect mode keeps adjacent taps safe while arrows still move', (
    tester,
  ) async {
    final moves = <String>[];
    await mount(tester, moves);
    final inspect = find.byKey(const ValueKey('tactical-inspect-mode'));
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(inspect).selected, isTrue);
    for (final (x, y) in [(36, 11), (35, 12)]) {
      await tapTile(tester, x, y);
      expect(moves, isEmpty);
      expect(find.text('Close tile details'), findsOneWidget);
      await tester.tap(find.text('Close tile details'));
      await tester.pumpAndSettle();
    }
    final right = find.byKey(const ValueKey('tactical-move:right'));
    await tester.ensureVisible(right);
    await tester.tap(right);
    await tester.pumpAndSettle();
    expect(moves, ['Right']);
    expect((game.locx, game.locy), (35, 11));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zooming and panning preserve the original tile hit coordinates',
    (tester) async {
      final moves = <String>[];
      await mount(tester, moves);
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('tactical-map-viewer')),
      );
      final controller = viewer.transformationController!;
      final initialScale = controller.value.getMaxScaleOnAxis();
      await tester.tap(find.byKey(const ValueKey('tactical-zoom-in')));
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(initialScale));
      final beforePan = controller.value.clone();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('tactical-map-viewport')),
      );
      await tester.dragFrom(viewport.center, const Offset(-44, 28));
      await tester.pumpAndSettle();
      final panDistance =
          (Offset(controller.value[12], controller.value[13]) -
                  Offset(beforePan[12], beforePan[13]))
              .distance;
      expect(panDistance, greaterThan(10));
      expect(
        moves,
        isEmpty,
        reason: 'Dragging the camera must not issue movement.',
      );
      await tapTile(tester, 36, 11);
      expect(moves, ['Right']);
      final painter =
          tester.widget<CustomPaint>(_grid).painter! as TacticalMapPainter;
      expect((painter.inspected?.x, painter.inspected?.y), (36, 11));
      expect((game.locx, game.locy), (35, 11));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hover details keep inspector and map viewport geometry stable', (
    tester,
  ) async {
    levelMap[36][11][0]
      ..firePeak = true
      ..restricted = true
      ..special = TileSpecial.insuranceClaimsTerminal;
    final moves = <String>[];
    await mount(tester, moves);
    final viewport = find.byKey(const ValueKey('tactical-map-viewport'));
    final initialInspector = tester.getRect(_inspector);
    final initialViewport = tester.getRect(viewport);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final (x, y) in [(37, 11), (36, 11), (35, 12), (34, 11), (35, 11)]) {
      await mouse.moveTo(_tileCenter(tester, x, y));
      await tester.pumpAndSettle();
      expect(tester.getRect(_inspector), initialInspector);
      expect(tester.getRect(viewport), initialViewport);
    }
    expect(moves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
