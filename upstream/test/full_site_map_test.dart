import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

void main() {
  setUp(() {
    game.gameState = game.GameState();
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
    levelMap[35][11][0].known = true;
    levelMap[5][5][0]
      ..known = true
      ..special = TileSpecial.bankVault;
    levelMap[6][5][0].special = TileSpecial.bankMoney;
  });

  test(
    'full floor extends the viewport while keeping unknown contents hidden',
    () {
      final small = TacticalMapSnapshot.capture();
      final full = TacticalMapSnapshot.capture(fullMap: true);
    expect(small.cells.any((cell) => cell.x == 5 && cell.y == 5), isFalse);
      expect(full.columnCount, MAPX);
      expect(full.rowCount, MAPY);
      expect(full.cells, hasLength(MAPX * MAPY));
    expect(full.cells[5 * MAPX + 5].label, 'Bank vault');
    expect(full.cells[5 * MAPX + 6].kind, TacticalTileKind.unknown);
    expect(full.cells[5 * MAPX + 6].label, 'Unexplored');
    expect(levelMap[6][5][0].known, isFalse);
    },
  );

  for (final width in [800.0, 1280.0]) {
    testWidgets(
      'graphical floor map fits $width and zoom stays in presentation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: FullSiteMap(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('full-site-map-grid')),
          findsOneWidget,
        );
        final before = game.date;
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await tester.tap(find.text('Fit floor'));
        await tester.pump();
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          1,
        );
        expect(game.date, before);
        expect(game.locx, 35);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
