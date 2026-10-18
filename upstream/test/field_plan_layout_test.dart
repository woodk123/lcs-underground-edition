import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Offset _tacticalTileCenter(WidgetTester tester, int x, int y) {
  final box = tester.renderObject<RenderBox>(_key('tactical-map-grid'));
  final snapshot = TacticalMapSnapshot.capture();
  final side = box.size.width / snapshot.columnCount;
  return box.localToGlobal(
    Offset(
      (x - snapshot.xStart + .5) * side,
      (y - snapshot.yStart + .5) * side,
    ),
  );
}

double _screenTileSize(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(_key('tactical-map-grid'));
  final side = box.size.width / TacticalMapSnapshot.columns;
  return (box.localToGlobal(Offset(side, 0)) - box.localToGlobal(Offset.zero))
          .distance *
      tester.view.devicePixelRatio;
}

Future<void> _tacticalControl(
  WidgetTester tester,
  String buttonKey,
  String menuLabel,
) async {
  final direct = _key(buttonKey);
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct);
  } else {
    await tester.tap(find.byTooltip('Map controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(menuLabel));
  }
  await tester.pumpAndSettle();
}

void _inside(WidgetTester tester, Finder finder, Rect bounds) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(bounds.left));
  expect(rect.right, lessThanOrEqualTo(bounds.right));
  expect(rect.top, greaterThanOrEqualTo(bounds.top));
  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
}

String _state() => jsonEncode({
  'game': game.gameState.toJson(),
  'position': [game.locx, game.locy, game.locz],
  'floor': [
    for (var y = 0; y < MAPY; y++)
      for (var x = 0; x < MAPX; x++)
        [
          levelMap[x][y][0].flag,
          levelMap[x][y][0].siegeflag,
          levelMap[x][y][0].inLOS,
          levelMap[x][y][0].special.name,
        ],
  ],
});

Future<List<int>> _pixels(TacticalMapSnapshot snapshot) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  TacticalMapPainter(snapshot).paint(canvas, const Size(460, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(460, 200);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = bytes!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  setUpAll(() async {
    await ensureGameDataLoaded();
    final font = FontLoader('JournalSerif');
    font.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    await font.load();
  });
  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    game.activeSite = Site(SiteType.warehouse)
      ..name = 'A known warehouse'
      ..compound.cameras = true;
    game.siteAlarm = true;
    game.postAlarmTimer = 81;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    for (var y = 7; y < 15; y++) {
      for (var x = 28; x < 41; x++) {
        levelMap[x][y][0]
          ..known = true
          ..inLOS = true;
      }
    }
    levelMap[35][10][0].wall = true;
    levelMap[35][12][0].door = true;
    levelMap[33][10][0].grass = true;
    levelMap[32][10][0].debris = true;
    levelMap[31][10][0].special = TileSpecial.stairsUp;
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    required Size window,
    required Size pane,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = window;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: window,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                key: const ValueKey('bounded-plan-pane'),
                width: pane.width,
                height: pane.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (window, pane) in [
    (const Size(1280, 720), const Size(800, 470)),
    (const Size(800, 600), const Size(560, 370)),
  ]) {
    testWidgets(
      'bounded tactical viewport and current action stay pinned at ${window.width} and 150%',
      (tester) async {
        levelMap[35][11][0].special = TileSpecial.radioBroadcastStudio;
        final moves = <String>[];
        await mount(
          tester,
          TacticalMapView(
            onMove: moves.add,
            showHeading: false,
            showMovementControls: false,
          ),
          window: window,
          pane: pane,
          scale: 1.5,
        );
        final grid = _key('tactical-map-grid');
        final parent = tester.getRect(_key('bounded-plan-pane'));
        expect(tester.getSize(grid).aspectRatio, closeTo(23 / 10, .0001));
        expect(_screenTileSize(tester), greaterThanOrEqualTo(31.999));
        final innerScroll = find.descendant(
          of: find.byType(TacticalMapView),
          matching: find.byType(SingleChildScrollView),
        );
        expect(innerScroll, findsNothing);
        final viewport = _key('tactical-map-viewport');
        final inspector = _key('tactical-tile-inspector');
        _inside(tester, viewport, parent);
        _inside(tester, inspector, parent);
        final currentTitle = find.descendant(
          of: inspector,
          matching: find.text('Current tile · Radio studio'),
        );
        final currentAction = find.descendant(
          of: inspector,
          matching: find.text('Press U to use / interact.'),
        );
        expect(currentTitle, findsOneWidget);
        expect(currentAction, findsOneWidget);
        _inside(tester, currentTitle, parent);
        _inside(tester, currentAction, parent);
        for (final label in [
          'Alarm raised',
          'Working cameras',
          'Response force arriving',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          _inside(tester, find.text(label), parent);
        }
        final keyButton = _key('field-plan-key-open');
        await tester.ensureVisible(keyButton);
        await tester.tap(keyButton);
        await tester.pumpAndSettle();
        final mapKey = _key('field-plan-key-dialog');
        expect(mapKey, findsOneWidget);
        for (final label in ['Loot', 'Unexplored']) {
          expect(
            find.descendant(of: mapKey, matching: find.text(label)),
            findsOneWidget,
          );
        }
        await tester.tap(_key('field-plan-key-close'));
        await tester.pumpAndSettle();
        _inside(tester, viewport, parent);
        expect(tester.getSize(viewport).height, greaterThan(32));
        await tester.tapAt(_tacticalTileCenter(tester, 36, 11));
        await tester.pumpAndSettle();
        expect(moves, [
          'Right',
        ], reason: 'Centering must retain exact tile hit coordinates.');
        await _tacticalControl(tester, 'tactical-fit', 'Fit area');
        final scene = tester.renderObject<RenderBox>(grid);
        final fittedScene = Rect.fromPoints(
          scene.localToGlobal(Offset.zero),
          scene.localToGlobal(scene.size.bottomRight(Offset.zero)),
        );
        final viewportRect = tester.getRect(viewport);
        expect(fittedScene.width, lessThanOrEqualTo(viewportRect.width + .001));
        expect(
          fittedScene.height,
          lessThanOrEqualTo(viewportRect.height + .001),
        );
        await _tacticalControl(
          tester,
          'tactical-center',
          'Center squad at readable size',
        );
        expect(_screenTileSize(tester), greaterThanOrEqualTo(31.999));
        expect(
          (_tacticalTileCenter(tester, 35, 11) -
                  tester.getRect(viewport).center)
              .distance,
          lessThan(.001),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'bounded full-floor plan fits ${window.width} at 150% and zooms around center',
      (tester) async {
        final before = _state();
        reseedRNG(seed: 615321);
        final rolls = List.generate(20, (_) => lcsRandom(100000));
        reseedRNG(seed: 615321);
        await mount(
          tester,
          const FullSiteMap(showHeading: false),
          window: window,
          pane: pane,
          scale: 1.5,
        );
        final grid = _key('full-site-map-grid');
        final parent = tester.getRect(_key('bounded-plan-pane'));
        _inside(tester, grid, parent);
        _inside(tester, _key('full-map-zoom-in'), parent);
        _inside(tester, _key('full-map-fit'), parent);
        final initial = tester.getSize(grid);
        expect(initial.width / initial.height, closeTo(MAPX / MAPY, .0001));
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final controller = viewer.transformationController!;
        final center = Offset(initial.width / 2, initial.height / 2);
        final sceneCenter = controller.toScene(center);
        await tester.tap(_key('full-map-zoom-in'));
        await tester.pump();
        final after = controller.toScene(center);
        expect(after.dx, closeTo(sceneCenter.dx, .001));
        expect(after.dy, closeTo(sceneCenter.dy, .001));
        expect(controller.value.getMaxScaleOnAxis(), 1.5);
        await tester.tap(_key('full-map-fit'));
        await tester.pump();
        expect(controller.value.getMaxScaleOnAxis(), 1);
        expect(_state(), before);
        expect(List.generate(20, (_) => lcsRandom(100000)), rolls);
        final painter =
            tester.widget<CustomPaint>(grid).painter! as TacticalMapPainter;
        expect(
          painter.onMove,
          isNull,
          reason: 'Full-floor inspection must stay passive.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the unbounded tactical plan uses its width beyond the former 690px cap',
    (tester) async {
      await mount(
        tester,
        SingleChildScrollView(child: TacticalMapView(onMove: (_) {})),
        window: const Size(1280, 720),
        pane: const Size(1000, 700),
      );
      final grid = tester.getSize(_key('tactical-map-grid'));
      expect(grid.width, greaterThan(900));
      expect(grid.width / grid.height, closeTo(23 / 10, .0001));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'opaque parchment fog renders identical pixels for different hidden contents',
    () async {
      final hidden = levelMap[25][8][0];
      expect(hidden.known, isFalse);
      final before = await _pixels(TacticalMapSnapshot.capture());
      hidden
        ..door = true
        ..wall = true
        ..loot = true
        ..restricted = true
        ..siegeHeavyUnit = true
        ..special = TileSpecial.bankVault
        ..firePeak = true;
      final after = await _pixels(TacticalMapSnapshot.capture());
      expect(after, before);
      expect(hidden.known, isFalse);
    },
  );
}
