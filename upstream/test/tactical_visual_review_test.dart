import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

import 'test_support.dart';

const _captureKey = ValueKey('tactical-artwork-review');
const _gridKey = ValueKey('tactical-map-grid');

/// A synthetic presentation fixture, not a saved game or gameplay playthrough.
/// Its intentionally mixed equipment puts every visual family in one room.
void _makeReviewFixture(SiteType type) {
  game.gameState = game.GameState();
  game.locx = 35;
  game.locy = 11;
  game.locz = 0;
  game.siteAlarm = false;
  game.siteAlarmTimer = -1;
  game.postAlarmTimer = 0;
  game.activeSite = Site(type)
    ..name = type == SiteType.amRadioStation
        ? 'QA fixture · AM Radio Station'
        : 'QA fixture · Warehouse';
  levelMap = List.generate(
    MAPX,
    (x) => List.generate(
      MAPY,
      (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
    ),
  );
  for (var y = 8; y <= 15; y++) {
    for (var x = 25; x <= 43; x++) {
      levelMap[x][y][0]
        ..known = true
        ..inLOS = x >= 29 || y >= 12
        ..wall = x == 25 || x == 43 || y == 8 || y == 15 || x == 34;
    }
  }
  for (var x = 35; x <= 43; x++) {
    levelMap[x][12][0].wall = true;
  }
  levelMap[34][11][0]
    ..wall = false
    ..door = true
    ..locked = true
    ..knownLock = true;
  levelMap[38][12][0]
    ..wall = false
    ..door = true
    ..locked = true
    ..knownLock = true
    ..cantUnlock = true;
  levelMap[29][8][0]
    ..wall = false
    ..door = true
    ..metal = true;
  levelMap[41][12][0]
    ..wall = false
    ..door = true
    ..fireStart = true;
  levelMap[25][11][0]
    ..wall = false
    ..exit = true;
  for (final (x, y, special) in [
    (36, 9, TileSpecial.radioBroadcastStudio),
    (38, 9, TileSpecial.computer),
    (40, 9, TileSpecial.ceoSafe),
    (42, 9, TileSpecial.corporateFiles),
    (36, 10, TileSpecial.table),
    (38, 10, TileSpecial.prisonControl),
    (40, 10, TileSpecial.labEquipment),
    (42, 10, TileSpecial.cagedRabbits),
    (27, 13, TileSpecial.polluterEquipment),
    (29, 13, TileSpecial.armory),
    (31, 13, TileSpecial.bankMoney),
    (33, 13, TileSpecial.displayCase),
    (27, 10, TileSpecial.parkBench),
    (29, 10, TileSpecial.tent),
    (31, 10, TileSpecial.securityCheckpoint),
    (26, 14, TileSpecial.stairsUp),
    (27, 14, TileSpecial.stairsDown),
  ]) {
    levelMap[x][y][0].special = special;
  }
  levelMap[37][14][0].siegeUnit = true;
  levelMap[39][14][0].siegeUnitDamaged = true;
  levelMap[41][14][0].siegeHeavyUnit = true;
  levelMap[37][13][0].fireStart = true;
  levelMap[39][13][0].firePeak = true;
  levelMap[41][13][0].fireEnd = true;
  levelMap[33][14][0].siegeTrap = true;
  levelMap[32][14][0].debris = true;
  levelMap[31][14][0].megaBloody = true;
  levelMap[30][14][0].bloody = true;
  levelMap[36][13][0].restricted = true;
  levelMap[27][9][0]
    ..grass = true
    ..outdoor = true;
  levelMap[28][9][0].outdoor = true;
  levelMap[35][11][0].special = TileSpecial.radioBroadcastStudio;
  // Unknown cells surround both rooms; this sentinel must remain hidden.
  levelMap[45][10][0]
    ..special = TileSpecial.bankVault
    ..siegeHeavyUnit = true;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      await _writePng(image, name);
    } finally {
      image.dispose();
    }
  });
}

Future<void> _writePng(ui.Image image, String name) async {
  final directory = await Directory(
    '../reports/tactical-artwork',
  ).create(recursive: true);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${directory.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
}

Future<List<int>> _planPixels(
  TacticalMapSnapshot snapshot,
  TacticalArt art,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  TacticalMapPainter(snapshot, art: art).paint(canvas, const Size(920, 400));
  final picture = recorder.endRecording();
  final image = await picture.toImage(920, 400);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void _galleryLabel(Canvas canvas, String text, Offset position, double width) {
  final label = TextPainter(
    text: TextSpan(
      text: text,
      style: JournalPalette.small.copyWith(fontSize: 10),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  label.paint(canvas, position);
}

/// Each crop is painted through the production atlas API at a readable 64 px.
Future<void> _captureGallery(WidgetTester tester, TacticalArt art) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 688, 430),
      Paint()..color = JournalPalette.page,
    );
    _galleryLabel(
      canvas,
      'SYNTHETIC QA GALLERY · INTERACTABLES · 64 px',
      const Offset(24, 12),
      640,
    );
    const objects = [
      'Radio console',
      'Workstation',
      'Safe',
      'Files',
      'Machinery',
      'Lab bench',
      'Control console',
      'Cage',
      'Table',
      'Crate',
      'Cash',
      'Rubble',
      'Bench',
      'Tent',
      'Display case',
      'Checkpoint',
    ];
    for (var index = 0; index < objects.length; index++) {
      final rect = Rect.fromLTWH(
        24 + (index % 8) * 80,
        42 + (index ~/ 8) * 112,
        64,
        64,
      );
      art.drawTerrain(
        canvas,
        rect,
        TacticalTerrainCell.studioCarpet,
        opacity: .52,
      );
      art.drawObject(canvas, rect, index);
      _galleryLabel(
        canvas,
        '${index + 1}. ${objects[index]}',
        rect.bottomLeft + const Offset(0, 5),
        76,
      );
    }
    _galleryLabel(
      canvas,
      'HAZARDS AND AFTERMATH · 64 px',
      const Offset(24, 274),
      640,
    );
    const hazards = [
      'Spreading fire',
      'Intense fire',
      'Embers',
      'Rubble',
      'Blood',
      'Heavy blood',
      'Trap',
      'Scorch',
    ];
    for (var index = 0; index < hazards.length; index++) {
      final rect = Rect.fromLTWH(24 + index * 80, 304, 64, 64);
      art.drawTerrain(canvas, rect, TacticalTerrainCell.concrete, opacity: .52);
      art.drawHazard(canvas, rect, index);
      _galleryLabel(
        canvas,
        '${index + 1}. ${hazards[index]}',
        rect.bottomLeft + const Offset(0, 5),
        76,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(688, 430);
    try {
      await _writePng(image, 'atlas-gallery');
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await ensureGameDataLoaded();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([serif.load(), sans.load(), icons.load()]);
  });

  for (final (name, size, scale, type) in [
    ('desktop', const Size(1000, 700), 1.0, SiteType.amRadioStation),
    ('compact', const Size(560, 500), 1.5, SiteType.warehouse),
  ]) {
    testWidgets('real tactical artwork renders in $name synthetic fixture', (
      tester,
    ) async {
      _makeReviewFixture(type);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });
      final moves = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: _captureKey,
                child: TacticalMapView(
                  onMove: moves.add,
                  // The operation shell has its own movement strip; keep the
                  // same bounded map configuration for the compact review.
                  showMovementControls: false,
                ),
              ),
            ),
          ),
        ),
      );
      final loadErrors = <Object>[];
      final context = tester.element(find.byType(TacticalMapView));
      await tester.runAsync(() async {
        await Future.wait([
          for (final asset in [
            tacticalTerrainAtlas.asset,
            tacticalObjectAtlas.asset,
            tacticalExtraObjectAtlas.asset,
            tacticalHazardAtlas.asset,
            JournalPalette.paperAsset,
          ])
            precacheImage(
              AssetImage(asset),
              context,
              onError: (error, stack) => loadErrors.add(error),
            ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(loadErrors, isEmpty);
      var painter =
          tester.widget<CustomPaint>(find.byKey(_gridKey)).painter!
              as TacticalMapPainter;
      expect(
        painter.art,
        isNotNull,
        reason:
            'Visual evidence must show decoded bitmap artwork, not vector fallbacks.',
      );
      expect(
        painter.snapshot.cells.any(
          (cell) => cell.kind == TacticalTileKind.unknown,
        ),
        isTrue,
      );
      expect(
        painter.snapshot.cells.any(
          (cell) => !cell.visible && cell.objectSprite != null,
        ),
        isTrue,
      );
      expect(
        painter.snapshot.cells
            .where((cell) => cell.objectSprite != null)
            .length,
        greaterThanOrEqualTo(15),
      );
      final defaultScene = tester.renderObject<RenderBox>(find.byKey(_gridKey));
      final logicalTile =
          defaultScene.size.width / painter.snapshot.columnCount;
      final physicalTile =
          (defaultScene.localToGlobal(Offset(logicalTile, 0)) -
                  defaultScene.localToGlobal(Offset.zero))
              .distance *
          tester.view.devicePixelRatio;
      expect(
        physicalTile,
        greaterThanOrEqualTo(31.999),
        reason:
            'The default compact plan must keep a readable focused tile size.',
      );
      if (name == 'desktop') {
        // Explicit overview evidence shows every fixture. Default compact
        // evidence below retains the real, readable zoom centered on squad.
        await tester.tap(find.byKey(const ValueKey('tactical-fit')));
        await tester.pumpAndSettle();
        final box = tester.renderObject<RenderBox>(find.byKey(_gridKey));
        final cellSize = box.size.width / painter.snapshot.columnCount;
        await tester.tapAt(
          box.localToGlobal(
            Offset(
              (40 - painter.snapshot.xStart + .5) * cellSize,
              (9 - painter.snapshot.yStart + .5) * cellSize,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      painter =
          tester.widget<CustomPaint>(find.byKey(_gridKey)).painter!
              as TacticalMapPainter;
      if (name == 'desktop') {
        expect(painter.inspected?.featureLabel, 'Safe');
      } else {
        expect(painter.inspected?.kind, TacticalTileKind.squad);
        expect(painter.inspected?.featureLabel, 'Radio studio');
      }
      expect(painter.art, isNotNull);
      expect(moves, isEmpty);
      expect(tester.takeException(), isNull);
      await _capture(tester, name);
      if (name == 'desktop') {
        await _captureGallery(tester, painter.art!);
        final before = await tester.runAsync(
          () => _planPixels(TacticalMapSnapshot.capture(), painter.art!),
        );
        levelMap[45][10][0]
          ..special = TileSpecial.radioBroadcastStudio
          ..wall = true
          ..grass = true
          ..firePeak = true
          ..siegeHeavyUnit = false
          ..siegeUnit = true
          ..inLOS = true;
        final after = await tester.runAsync(
          () => _planPixels(TacticalMapSnapshot.capture(), painter.art!),
        );
        expect(
          after,
          before,
          reason:
              'Loaded bitmap artwork must not expose any hidden terrain, '
              'objects, hazards, or threats through opaque fog.',
        );
        expect(levelMap[45][10][0].known, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
