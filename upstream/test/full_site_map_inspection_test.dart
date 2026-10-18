import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
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

Finder get _grid => find.byKey(const ValueKey('full-site-map-grid'));
Finder get _inspector => find.byKey(const ValueKey('full-map-tile-inspector'));
Finder _key(String value) => find.byKey(ValueKey(value));

TacticalMapPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_grid).painter! as TacticalMapPainter;

TransformationController _controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

Offset _tileCenter(WidgetTester tester, int x, int y) {
  final grid = tester.renderObject<RenderBox>(_grid);
  final cellSize = grid.size.width / MAPX;
  return grid.localToGlobal(Offset((x + .5) * cellSize, (y + .5) * cellSize));
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
    game.activeSite = Site(SiteType.amRadioStation);
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    levelMap[35][11][0]
      ..known = true
      ..inLOS = true;
    levelMap[37][12][0]
      ..known = true
      ..inLOS = true
      ..restricted = true
      ..special = TileSpecial.radioBroadcastStudio;
    levelMap[38][12][0]
      ..special = TileSpecial.bankVault
      ..firePeak = true
      ..siegeHeavyUnit = true
      ..restricted = true
      ..inLOS = true;
    levelMap[35][11][1].known = true;
  });

  Widget app({Size pane = const Size(900, 650), double textScale = 1}) =>
      MaterialApp(
        theme: buildJournalTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1100, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                key: const ValueKey('full-map-test-pane'),
                width: pane.width,
                height: pane.height,
                child: const FullSiteMap(showHeading: false),
              ),
            ),
          ),
        ),
      );

  Future<void> mount(
    WidgetTester tester, {
    Size pane = const Size(900, 650),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(pane: pane, textScale: textScale));
    await tester.pumpAndSettle();
  }

  Future<void> zoomAndPan(WidgetTester tester) async {
    await tester.tap(_key('full-map-zoom-in'));
    await tester.pumpAndSettle();
    final before = _controller(tester).value.clone();
    await tester.dragFrom(
      tester.getCenter(find.byType(InteractiveViewer)),
      const Offset(45, 25),
    );
    await tester.pumpAndSettle();
    expect(_controller(tester).value.getMaxScaleOnAxis(), closeTo(1.5, .001));
    expect(_controller(tester).value[12], isNot(before[12]));
  }

  testWidgets('zoomed and panned taps inspect the transformed cell', (
    tester,
  ) async {
    await mount(tester);
    await zoomAndPan(tester);
    await tester.tapAt(_tileCenter(tester, 37, 12));
    await tester.pumpAndSettle();
    final selected = _painter(tester).inspected!;
    expect((selected.x, selected.y), (37, 12));
    expect(_inspectorText(tester), contains('Radio studio'));
    expect(_inspectorText(tester), contains('Restricted'));
    expect(_painter(tester).onMove, isNull);
    expect((game.locx, game.locy), (35, 11));

    await tester.tap(_key('full-map-fit'));
    await tester.pumpAndSettle();
    expect(_controller(tester).value, Matrix4.identity());
    expect(
      find.text('Inspection only — return to operation to move'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover and touch inspection cannot reveal hidden contents', (
    tester,
  ) async {
    await mount(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(_tileCenter(tester, 37, 12));
    await tester.pumpAndSettle();
    expect(_painter(tester).inspected!.label, contains('Radio studio'));
    await mouse.moveTo(_tileCenter(tester, 38, 12));
    await tester.pumpAndSettle();
    expect(_painter(tester).inspected!.kind, TacticalTileKind.unknown);
    expect(_inspectorText(tester), contains('Unexplored'));
    expect(_inspectorText(tester), isNot(contains('vault')));
    expect(_inspectorText(tester), isNot(contains('Armored')));
    expect(_inspectorText(tester), isNot(contains('Fire')));
    await mouse.removePointer();
    await tester.tapAt(_tileCenter(tester, 38, 12));
    await tester.pumpAndSettle();
    expect(_inspectorText(tester), contains('Unexplored'));
    expect(levelMap[38][12][0].known, isFalse);
  });

  testWidgets('full-floor inspection, zoom and pan preserve state and RNG', (
    tester,
  ) async {
    final before = _state();
    reseedRNG(seed: 671324);
    final expectedRolls = List.generate(20, (_) => lcsRandom(100000));
    reseedRNG(seed: 671324);
    await mount(tester);
    await zoomAndPan(tester);
    await tester.longPressAt(_tileCenter(tester, 37, 12));
    await tester.pumpAndSettle();
    expect(
      (_painter(tester).inspected!.x, _painter(tester).inspected!.y),
      (37, 12),
    );
    await tester.tapAt(_tileCenter(tester, 38, 12));
    await tester.tap(_key('full-map-fit'));
    await tester.pumpAndSettle();
    expect(_state(), before);
    expect(List.generate(20, (_) => lcsRandom(100000)), expectedRolls);
    expect(_painter(tester).onMove, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing floors clears the previous floor selection', (
    tester,
  ) async {
    await mount(tester);
    await tester.tapAt(_tileCenter(tester, 37, 12));
    await tester.pumpAndSettle();
    expect(_painter(tester).inspected, isNotNull);
    game.locz = 1;
    tester.element(find.byType(FullSiteMap)).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(_painter(tester).snapshot.floor, 1);
    expect(_painter(tester).inspected, isNull);
    expect(_inspectorText(tester), isNot(contains('Radio studio')));
  });

  for (final height in [220.0, 450.0]) {
    testWidgets('full map fits a 560 × $height pane at 150% text', (
      tester,
    ) async {
      await mount(tester, pane: Size(560, height), textScale: 1.5);
      final pane = tester.getRect(_key('full-map-test-pane'));
      await tester.tapAt(_tileCenter(tester, 37, 12));
      await tester.pumpAndSettle();
      expect(_inspectorText(tester), contains('Radio studio'));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_grid).aspectRatio, closeTo(MAPX / MAPY, .0001));
      if (height < 280) {
        expect(_key('full-map-scroll'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Inspection only — return to operation to move'),
        );
        await tester.pumpAndSettle();
      }
      final status = tester.getRect(
        find.text('Inspection only — return to operation to move'),
      );
      expect(status.top, greaterThanOrEqualTo(pane.top));
      expect(status.bottom, lessThanOrEqualTo(pane.bottom));
      expect(status.left, greaterThanOrEqualTo(pane.left));
      expect(status.right, lessThanOrEqualTo(pane.right));
      expect(tester.takeException(), isNull);
    });
  }
}
