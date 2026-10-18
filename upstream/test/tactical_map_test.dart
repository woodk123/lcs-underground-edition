import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

TacticalMapCell cellAt(TacticalMapSnapshot snapshot, int x, int y) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

void main() {
  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    game.siteAlarmTimer = -1;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    levelMap[35][11][0].known = true;
  });

  test(
    'unknown terrain, loot, special rooms and foes produce identical fog',
    () {
      final hidden = levelMap[36][11][0]
        ..wall = true
        ..door = true
        ..loot = true
        ..restricted = true
        ..firePeak = true
        ..siegeUnit = true
        ..inLOS = true
        ..special = TileSpecial.bankVault;
      final snapshot = TacticalMapSnapshot.capture();
      final cell = cellAt(snapshot, hidden.x, hidden.y);
      final empty = cellAt(snapshot, 37, 11);
      expect(cell.kind, TacticalTileKind.unknown);
      expect(cell.label, empty.label);
      expect(cell.icon, isNull);
      expect(cell.visible, isFalse);
      expect(cell.burning, isFalse);
      expect(cell.restricted, isFalse);
      expect(cell.horizontalDoor, isFalse);
      expect(snapshot.cells.length, 230);
      expect(
        hidden.known,
        isFalse,
        reason: 'Rendering must not explore tiles.',
      );
      expect(
        hidden.inLOS,
        isTrue,
        reason: 'Rendering must not recalculate LOS.',
      );
    },
  );

  test('known foes stay hidden outside LOS and appear when visible', () {
    final enemy = levelMap[36][11][0]
      ..known = true
      ..siegeUnit = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.floor,
    );
    expect(cellAt(TacticalMapSnapshot.capture(), 36, 11).label, 'Open floor');
    enemy.inLOS = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.enemy,
    );
    enemy
      ..siegeUnit = false
      ..siegeUnitDamaged = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.woundedEnemy,
    );
    enemy.siegeHeavyUnit = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.armoredEnemy,
    );
  });

  test('working cameras reveal only foes on already known tiles', () {
    final site = Site(SiteType.warehouse);
    game.activeSite = site;
    site.compound.cameras = true;
    levelMap[36][11][0]
      ..known = true
      ..siegeUnit = true;
    levelMap[37][11][0].siegeHeavyUnit = true;
    var snapshot = TacticalMapSnapshot.capture();
    expect(snapshot.cameras, isTrue);
    expect(cellAt(snapshot, 36, 11).kind, TacticalTileKind.enemy);
    expect(cellAt(snapshot, 37, 11).kind, TacticalTileKind.unknown);
    site.siege.camerasOff = true;
    snapshot = TacticalMapSnapshot.capture();
    expect(snapshot.cameras, isFalse);
    expect(cellAt(snapshot, 36, 11).kind, TacticalTileKind.floor);
  });

  test('squad marker uses the exact player tile on the current floor', () {
    game.locx = 50;
    game.locy = 18;
    game.locz = 3;
    levelMap[50][18][3]
      ..known = true
      ..wall = true
      ..siegeUnit = true
      ..firePeak = true
      ..special = TileSpecial.stairsDown;
    levelMap[35][11][3].known = true;
    final snapshot = TacticalMapSnapshot.capture();
    final squad = snapshot.cells.singleWhere(
      (cell) => cell.kind == TacticalTileKind.squad,
    );
    expect((squad.x, squad.y), (50, 18));
    expect(snapshot.floor, 3);
    expect(snapshot.currentDescription, 'Stairs down · Fire');
    expect(squad.label, 'Squad');
  });

  test('viewport clamping matches all four classic map edges', () {
    for (final (x, y, xStart, yStart) in [
      (0, 0, 0, 0),
      (MAPX - 1, 0, MAPX - 23, 0),
      (0, MAPY - 1, 0, MAPY - 10),
      (MAPX - 1, MAPY - 1, MAPX - 23, MAPY - 10),
      (35, 11, 24, 7),
    ]) {
      game.locx = x;
      game.locy = y;
      final snapshot = TacticalMapSnapshot.capture();
      expect((snapshot.xStart, snapshot.yStart), (xStart, yStart));
      expect(
        (snapshot.cells.first.x, snapshot.cells.first.y),
        (xStart, yStart),
      );
      expect(
        (snapshot.cells.last.x, snapshot.cells.last.y),
        (xStart + 22, yStart + 9),
      );
    }
  });

  test('tile priority and undiscovered lock state match the engine', () {
    final tile = levelMap[36][11][0]
      ..known = true
      ..inLOS = true
      ..door = true
      ..locked = true
      ..siegeHeavyUnit = true
      ..special = TileSpecial.stairsUp;
    var cell = cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.kind, TacticalTileKind.door);
    expect(cell.label, 'Door', reason: 'An undiscovered lock remains hidden.');
    tile.knownLock = true;
    expect(cellAt(TacticalMapSnapshot.capture(), 36, 11).label, 'Locked door');
    tile.cantUnlock = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).label,
      'Door · cannot unlock',
    );
    tile.metal = true;
    expect(cellAt(TacticalMapSnapshot.capture(), 36, 11).label, 'Metal door');
    tile.door = false;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.armoredEnemy,
    );
    tile.siegeHeavyUnit = false;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.stairsUp,
    );
    tile
      ..special = TileSpecial.none
      ..exit = true
      ..firePeak = true;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.exit,
    );
    tile.exit = false;
    expect(
      cellAt(TacticalMapSnapshot.capture(), 36, 11).kind,
      TacticalTileKind.fire,
    );
    tile
      ..firePeak = false
      ..special = TileSpecial.corporateFiles
      ..loot = true;
    cell = cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.kind, TacticalTileKind.special);
    expect(cell.label, 'Corporate files');
    expect(cell.icon, Icons.folder_copy_rounded);
  });

  test(
    'accessible map labels never expose unseen foes or unknown features',
    () {
      levelMap[36][11][0]
        ..known = true
        ..siegeUnit = true;
      levelMap[37][11][0]
        ..special = TileSpecial.bankVault
        ..siegeHeavyUnit = true;
      final painter = TacticalMapPainter(TacticalMapSnapshot.capture());
      final semantics = painter.semanticsBuilder(const Size(690, 300));
      final labels = semantics.map((cell) => cell.properties.label).join(' ');
      expect(labels, contains(RegExp(r'Squad[^,]*, column 36, row 12')));
      expect(labels, contains('Current position'));
      expect(labels, contains(RegExp(r'Open floor[^,]*, column 37, row 12')));
      expect(labels, contains('Previously explored'));
      expect(labels, isNot(contains('Enemy')));
      expect(labels, isNot(contains('Armored')));
      expect(labels, isNot(contains('vault')));
      expect(labels, isNot(contains('column 38')));
    },
  );

  for (final width in [360.0, 900.0]) {
    testWidgets('map fits $width px and forwards only directional inputs', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final inputs = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TacticalMapView(onMove: inputs.add),
            ),
          ),
        ),
      );
      for (final direction in ['up', 'down', 'left', 'right']) {
        await tester.ensureVisible(find.byTooltip('Move $direction'));
        await tester.tap(find.byTooltip('Move $direction'));
      }
      expect(inputs, ['Up', 'Down', 'Left', 'Right']);
      expect(find.text('Current tile · Open floor'), findsOneWidget);
      expect(find.text('LEVEL 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
