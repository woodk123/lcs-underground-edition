import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
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
    levelMap[36][11][0].known = true;
    levelMap[37][11][0].known = true;
    levelMap[35][10][0]
      ..known = true
      ..wall = true;
    levelMap[35][12][0]
      ..known = true
      ..door = true;
  });

  Future<void> mount(
    WidgetTester tester,
    List<String> moves, {
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TacticalMapView(onMove: moves.add, movementEnabled: enabled),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, int x, int y) async {
    final grid = find.byKey(const ValueKey('tactical-map-grid'));
    final box = tester.renderObject<RenderBox>(grid);
    final cell = box.size.width / TacticalMapSnapshot.columns;
    final snapshot = TacticalMapSnapshot.capture();
    await tester.tapAt(
      box.localToGlobal(
        Offset(
          (x - snapshot.xStart + .5) * cell,
          (y - snapshot.yStart + .5) * cell,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'clicking the adjacent floor or door sends the original direction',
    (tester) async {
      final moves = <String>[];
      await mount(tester, moves);
      await tapTile(tester, 36, 11);
      await tapTile(tester, 35, 12);
      expect(moves, ['Right', 'Down']);
      expect(
        game.locx,
        35,
        reason:
            'The renderer sends commands; the original engine owns movement.',
      );
      expect(levelMap[35][12][0].door, isTrue);
    },
  );

  testWidgets('distant, unknown and wall cells cannot initiate movement', (
    tester,
  ) async {
    final moves = <String>[];
    await mount(tester, moves);
    await tapTile(tester, 37, 11);
    await tapTile(tester, 34, 11);
    await tapTile(tester, 35, 10);
    expect(moves, isEmpty);
    expect(levelMap[34][11][0].known, isFalse);
  });

  testWidgets('blocked movement disables both tile and directional controls', (
    tester,
  ) async {
    final moves = <String>[];
    await mount(tester, moves, enabled: false);
    await tapTile(tester, 36, 11);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('tactical-move:right')))
          .onPressed,
      isNull,
    );
    expect(moves, isEmpty);
  });
}
