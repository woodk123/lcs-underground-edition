import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/modern/tactical_symbols.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

import 'test_support.dart';

const _captureKey = ValueKey('supplemental-artwork-review');
const _localGridKey = ValueKey('tactical-map-grid');
const _fullGridKey = ValueKey('full-site-map-grid');

const _extraLabels = [
  'Detention cell',
  'Patient bed',
  'Executive desk',
  'Presidential desk',
  'Teller counter',
  'Bank vault',
  'Jury table',
  'Signboard',
  'TV camera',
  'Server rack',
  'Sewing machine',
  'Reactor console',
  'Weapon rack',
  'Prison console',
  'Office desk',
  'Claims terminal',
];

/// Deliberately mixed synthetic fixture, not a saved game or playthrough.
/// Every supplemental crop and the compound status cases share one known room.
void _makeFixture() {
  game.gameState = game.GameState();
  game.locx = 35;
  game.locy = 11;
  game.locz = 0;
  game.siteAlarm = false;
  game.siteAlarmTimer = -1;
  game.postAlarmTimer = 0;
  game.activeSite = Site(SiteType.courthouse)
    ..name = 'SYNTHETIC QA fixture · Supplemental artwork';
  levelMap = List.generate(
    MAPX,
    (x) => List.generate(
      MAPY,
      (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
    ),
  );
  for (var y = 8; y <= 15; y++) {
    for (var x = 25; x <= 44; x++) {
      levelMap[x][y][0]
        ..known = true
        ..inLOS = true
        ..wall = x == 25 || x == 44 || y == 8 || y == 15;
    }
  }
  levelMap[25][11][0]
    ..wall = false
    ..exit = true;
  for (final (x, y, special) in [
    (26, 9, TileSpecial.policeStationLockup),
    (28, 9, TileSpecial.nursingHomePatient),
    (30, 9, TileSpecial.ceoOffice),
    (32, 9, TileSpecial.ovalOfficeNW),
    (33, 9, TileSpecial.ovalOfficeNE),
    (32, 10, TileSpecial.ovalOfficeSW),
    (33, 10, TileSpecial.ovalOfficeSE),
    (35, 9, TileSpecial.bankTeller),
    (37, 9, TileSpecial.bankVault),
    (39, 9, TileSpecial.courthouseJuryRoom),
    (41, 9, TileSpecial.signOne),
    (26, 11, TileSpecial.cableBroadcastStudio),
    (28, 11, TileSpecial.intelSupercomputer),
    (30, 11, TileSpecial.sweatshopEquipment),
    (32, 11, TileSpecial.nuclearControlRoom),
    (37, 11, TileSpecial.armory),
    (39, 11, TileSpecial.prisonControlHigh),
    (41, 11, TileSpecial.apartmentLandlord),
    (43, 11, TileSpecial.insuranceClaimsTerminal),
    (28, 13, TileSpecial.nursingHomePatientDone),
    (31, 13, TileSpecial.nursingHomePatientDone),
    (37, 13, TileSpecial.radioBroadcastStudio),
    (39, 13, TileSpecial.ceoSafe),
    (41, 13, TileSpecial.labEquipment),
  ]) {
    levelMap[x][y][0].special = special;
  }
  // Flags belong to the wall's explored neighboring tile in the engine.
  levelMap[27][9][0].graffitiLCS = true;
  levelMap[36][9][0].graffitiCCS = true;
  levelMap[42][9][0].graffitiOther = true;
  levelMap[31][13][0]
    ..firePeak = true
    ..siegeUnit = true
    ..siegeTrap = true;
  // Previously explored equipment must retain its form under the memory tint.
  levelMap[26][11][0].inLOS = false;
  // An adjacent unexplored sentinel must stay absent from the presentation.
  levelMap[45][10][0]
    ..special = TileSpecial.bankVault
    ..firePeak = true
    ..siegeHeavyUnit = true;
}

TacticalMapCell _cell(TacticalMapSnapshot snapshot, int x, int y) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

String _state() => jsonEncode({
  'game': game.gameState.toJson(),
  'position': [game.locx, game.locy, game.locz],
  'tiles': [
    for (final tile in levelMap.all)
      [tile.flag, tile.siegeflag, tile.inLOS, tile.special.name],
  ],
});

TacticalMapPainter _painter(WidgetTester tester, {bool full = false}) =>
    tester
            .widget<CustomPaint>(
              find.byKey(full ? _fullGridKey : _localGridKey),
            )
            .painter!
        as TacticalMapPainter;

Future<void> _writePng(ui.Image image, String name) async {
  final directory = await Directory(
    '../reports/tactical-supplemental',
  ).create(recursive: true);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${directory.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
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

void _label(Canvas canvas, String text, Offset position, double width) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: JournalPalette.small.copyWith(fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  painter.paint(canvas, position);
  painter.dispose();
}

void _object(Canvas canvas, TacticalArt art, Rect rect, int index) {
  art.drawTerrain(canvas, rect, TacticalTerrainCell.flagstone, opacity: .52);
  art.drawObject(canvas, rect, index);
}

/// Raw sprite comparisons use the actual production atlas crop/draw method.
/// Each supplemental illustration appears at both target review sizes.
Future<void> _captureGallery(WidgetTester tester, TacticalArt art) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 944, 832),
      Paint()..color = JournalPalette.page,
    );
    _label(
      canvas,
      'SYNTHETIC QA GALLERY · ALL 16 SUPPLEMENTAL SPRITES · PRODUCTION ATLAS API',
      const Offset(20, 14),
      904,
    );
    for (var index = 0; index < _extraLabels.length; index++) {
      final x = 20 + (index % 4) * 228.0;
      final y = 50 + (index ~/ 4) * 150.0;
      _label(
        canvas,
        '${index + 16}. ${_extraLabels[index]}',
        Offset(x, y),
        212,
      );
      _object(
        canvas,
        art,
        Rect.fromLTWH(x + 8, y + 40, 32, 32),
        index + tacticalObjectAtlas.cellCount,
      );
      _object(
        canvas,
        art,
        Rect.fromLTWH(x + 86, y + 24, 64, 64),
        index + tacticalObjectAtlas.cellCount,
      );
      _label(canvas, '32 px', Offset(x + 8, y + 98), 60);
      _label(canvas, '64 px', Offset(x + 86, y + 98), 74);
    }
    _label(
      canvas,
      'EXISTING ARTWORK · 32 / 64 px · SAME FLOOR, CROP API AND SCALE FOR COMPARISON',
      const Offset(20, 666),
      904,
    );
    const legacy = [
      (TacticalObjectCell.radioConsole, 'Radio console'),
      (TacticalObjectCell.controlConsole, 'Control console'),
      (TacticalObjectCell.safe, 'Small safe'),
      (TacticalObjectCell.labBench, 'Lab bench'),
      (TacticalObjectCell.table, 'Ordinary table'),
      (TacticalObjectCell.crate, 'Loot crate'),
    ];
    for (var index = 0; index < legacy.length; index++) {
      final x = 20 + index * 152.0;
      _object(canvas, art, Rect.fromLTWH(x, 714, 32, 32), legacy[index].$1);
      _object(
        canvas,
        art,
        Rect.fromLTWH(x + 54, 698, 64, 64),
        legacy[index].$1,
      );
      _label(canvas, '32 px', Offset(x, 770), 46);
      _label(canvas, '64 px', Offset(x + 54, 770), 60);
      _label(canvas, legacy[index].$2, Offset(x, 794), 140);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(944, 832);
    try {
      await _writePng(image, 'atlas-gallery-32-64');
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
}

TacticalMapSnapshot _isolatedCells(
  TacticalMapSnapshot source,
  List<TacticalMapCell> cells, {
  int columns = 1,
  int rows = 1,
}) => TacticalMapSnapshot(
  xStart: cells.first.x,
  yStart: cells.first.y,
  floor: source.floor,
  cells: cells,
  location: 'Synthetic status detail',
  currentDescription: '',
  alarm: source.alarm,
  cameras: false,
  response: '',
  columnCount: columns,
  rowCount: rows,
  siteType: source.siteType,
);

/// Status combinations are painted by TacticalMapPainter, including lettering,
/// wall marks, visited checks, fire, units, traps and the four desk quadrants.
Future<void> _captureDetails(
  WidgetTester tester,
  TacticalArt art,
  TacticalMapSnapshot snapshot,
) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 944, 448),
      Paint()..color = JournalPalette.page,
    );
    _label(
      canvas,
      'SYNTHETIC QA · PRODUCTION MAP PAINTER · STATUS COMBINATIONS AT 32 / 64 px',
      const Offset(20, 14),
      904,
    );
    const details = [
      (27, 8, 'LCS wall graffiti'),
      (36, 8, 'CCS wall graffiti'),
      (42, 8, 'Other wall graffiti'),
      (28, 13, 'Visited patient room'),
      (31, 13, 'Visited + enemy + fire + trap'),
      (41, 9, 'Signboard + lettering'),
    ];
    for (var index = 0; index < details.length; index++) {
      final x = 20 + (index % 3) * 304.0;
      final y = 50 + (index ~/ 3) * 150.0;
      final (tileX, tileY, name) = details[index];
      _label(canvas, name, Offset(x, y), 286);
      for (final (size, offset) in [(32.0, 8.0), (64.0, 88.0)]) {
        canvas.save();
        canvas.translate(x + offset, y + 28);
        TacticalMapPainter(
          _isolatedCells(snapshot, [_cell(snapshot, tileX, tileY)]),
          art: art,
        ).paint(canvas, Size(size, size));
        canvas.restore();
        _label(canvas, '${size.toInt()} px', Offset(x + offset, y + 100), 74);
      }
    }
    _label(
      canvas,
      'Joined presidential desk · four engine tiles · 32 px per tile',
      const Offset(20, 360),
      520,
    );
    final desk = _isolatedCells(
      snapshot,
      [
        _cell(snapshot, 32, 9),
        _cell(snapshot, 33, 9),
        _cell(snapshot, 32, 10),
        _cell(snapshot, 33, 10),
      ],
      columns: 2,
      rows: 2,
    );
    canvas.save();
    canvas.translate(572, 356);
    TacticalMapPainter(desk, art: art).paint(canvas, const Size(64, 64));
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(944, 448);
    try {
      await _writePng(image, 'status-details-32-64');
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
}

Future<void> _precache(WidgetTester tester, {bool full = false}) async {
  final errors = <Object>[];
  final context = tester.element(
    find.byType(full ? FullSiteMap : TacticalMapView),
  );
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
          onError: (error, stack) => errors.add(error),
        ),
    ]);
  });
  await tester.pumpAndSettle();
  expect(errors, isEmpty);
  expect(
    _painter(tester, full: full).art,
    isNotNull,
    reason: 'Screenshot evidence must contain decoded bitmaps, not fallbacks.',
  );
}

void _verifyFixture(TacticalMapSnapshot snapshot) {
  expect(
    snapshot.cells.map((cell) => cell.objectSprite).whereType<int>().toSet(),
    containsAll(List.generate(16, (index) => index + 16)),
  );
  expect(_cell(snapshot, 27, 8).graffiti, TacticalGraffiti.lcs);
  expect(_cell(snapshot, 36, 8).graffiti, TacticalGraffiti.ccs);
  expect(_cell(snapshot, 42, 8).graffiti, TacticalGraffiti.other);
  expect(_cell(snapshot, 28, 13).visited, isTrue);
  final compound = _cell(snapshot, 31, 13);
  expect(compound.kind, TacticalTileKind.enemy);
  expect(compound.visited && compound.burning, isTrue);
  expect(compound.hazardLabel, contains('Defensive boobytrap'));
  expect(compound.objectSprite, TacticalObjectCell.nursingBed);
  expect(
    [
      _cell(snapshot, 32, 9).objectQuadrant,
      _cell(snapshot, 33, 9).objectQuadrant,
      _cell(snapshot, 32, 10).objectQuadrant,
      _cell(snapshot, 33, 10).objectQuadrant,
    ],
    [0, 1, 2, 3],
  );
  expect(_cell(snapshot, 45, 10).kind, TacticalTileKind.unknown);
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

  for (final (name, size, full) in [
    ('desktop-150', const Size(1100, 800), false),
    ('compact-150', const Size(560, 560), false),
    ('full-site-150', const Size(1100, 800), true),
  ]) {
    testWidgets('supplemental bitmap review in synthetic $name fixture', (
      tester,
    ) async {
      _makeFixture();
      final before = _state();
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
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: _captureKey,
                child: full
                    ? const FullSiteMap()
                    : TacticalMapView(
                        onMove: moves.add,
                        showMovementControls: false,
                        movementEnabled: false,
                      ),
              ),
            ),
          ),
        ),
      );
      await _precache(tester, full: full);
      _verifyFixture(_painter(tester, full: full).snapshot);
      expect(tester.takeException(), isNull);

      if (full) {
        // Full-floor overview is useful evidence of scale and fog boundaries.
        await _capture(tester, name);
        await tester.tap(find.byKey(const ValueKey('full-map-find-squad')));
        await tester.pumpAndSettle();
        await _capture(tester, 'full-site-focused-150');
      } else {
        await _capture(tester, name);
        if (name == 'desktop-150') {
          await tester.tap(find.byKey(const ValueKey('tactical-fit')));
          await tester.pumpAndSettle();
          final painter = _painter(tester);
          final grid = tester.renderObject<RenderBox>(
            find.byKey(_localGridKey),
          );
          final cellSize = grid.size.width / painter.snapshot.columnCount;
          await tester.tapAt(
            grid.localToGlobal(
              Offset(
                (31 - painter.snapshot.xStart + .5) * cellSize,
                (13 - painter.snapshot.yStart + .5) * cellSize,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final inspected = _painter(tester);
          expect(inspected.inspected?.visited, isTrue);
          expect(inspected.inspected?.burning, isTrue);
          await _capture(tester, 'desktop-overview-inspected-150');
          await _captureGallery(tester, inspected.art!);
          await _captureDetails(tester, inspected.art!, inspected.snapshot);
        }
      }
      expect(_painter(tester, full: full).art, isNotNull);
      expect(moves, isEmpty);
      expect(
        _state(),
        before,
        reason: 'Review interactions must be read-only.',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
