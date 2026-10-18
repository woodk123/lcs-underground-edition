import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

// Independent acceptance coverage for the requested families, including every
// alternate engine state. These are declared presentation fixtures, not earned
// gameplay outcomes or a claim about native Windows play.
const _scope = <(TileSpecial, int)>[
  (TileSpecial.policeStationLockup, TacticalObjectCell.detentionCell),
  (TileSpecial.courthouseLockup, TacticalObjectCell.detentionCell),
  (TileSpecial.nursingHomePatient, TacticalObjectCell.nursingBed),
  (TileSpecial.nursingHomePatientDone, TacticalObjectCell.nursingBed),
  (TileSpecial.ceoOffice, TacticalObjectCell.executiveDesk),
  (TileSpecial.insuranceCEO, TacticalObjectCell.executiveDesk),
  (TileSpecial.nursingHomeManager, TacticalObjectCell.officeDesk),
  (TileSpecial.apartmentLandlord, TacticalObjectCell.officeDesk),
  (TileSpecial.ovalOfficeNW, TacticalObjectCell.presidentialDesk),
  (TileSpecial.ovalOfficeNE, TacticalObjectCell.presidentialDesk),
  (TileSpecial.ovalOfficeSW, TacticalObjectCell.presidentialDesk),
  (TileSpecial.ovalOfficeSE, TacticalObjectCell.presidentialDesk),
  (TileSpecial.bankTeller, TacticalObjectCell.tellerCounter),
  (TileSpecial.bankVault, TacticalObjectCell.bankVault),
  (TileSpecial.courthouseJuryRoom, TacticalObjectCell.juryTable),
  (TileSpecial.cableBroadcastStudio, TacticalObjectCell.tvCamera),
  (TileSpecial.intelSupercomputer, TacticalObjectCell.serverRack),
  (TileSpecial.sweatshopEquipment, TacticalObjectCell.sewingMachine),
  (TileSpecial.nuclearControlRoom, TacticalObjectCell.reactorConsole),
  (TileSpecial.prisonControl, TacticalObjectCell.prisonConsole),
  (TileSpecial.prisonControlLow, TacticalObjectCell.prisonConsole),
  (TileSpecial.prisonControlMedium, TacticalObjectCell.prisonConsole),
  (TileSpecial.prisonControlHigh, TacticalObjectCell.prisonConsole),
  (TileSpecial.insuranceClaimsTerminal, TacticalObjectCell.claimsTerminal),
  (TileSpecial.armory, TacticalObjectCell.weaponRack),
  (TileSpecial.signOne, TacticalObjectCell.signboard),
  (TileSpecial.signTwo, TacticalObjectCell.signboard),
  (TileSpecial.signThree, TacticalObjectCell.signboard),
];

TacticalMapCell _cell(TacticalMapSnapshot snapshot, [int x = 36, int y = 11]) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

String _state() => jsonEncode({
  'game': game.gameState.toJson(),
  'position': [game.locx, game.locy, game.locz],
  'tiles': [
    for (final tile in levelMap.all)
      [tile.flag, tile.siegeflag, tile.inLOS, tile.special.name],
  ],
});

Future<List<int>> _spritePixels(TacticalArt art, int index) async {
  return _paintPixels(
    32,
    (canvas) =>
        art.drawObject(canvas, const Rect.fromLTWH(0, 0, 32, 32), index),
  );
}

Future<List<int>> _paintPixels(
  int side,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<List<int>> _combinedStatusPixels(
  TacticalArt art, {
  required bool visited,
  required bool trap,
}) => _paintPixels(32, (canvas) {
  final cell = TacticalMapCell(
    x: 0,
    y: 0,
    kind: TacticalTileKind.squad,
    label: 'Squad',
    visible: true,
    restricted: true,
    burning: true,
    underlyingKind: TacticalTileKind.special,
    underlyingLabel: 'Patient’s room',
    objectSprite: TacticalObjectCell.nursingBed,
    hazardSprite: TacticalHazardCell.intenseFire,
    hazardLabel: trap ? 'Intense fire · Defensive boobytrap' : 'Intense fire',
    pointOfInterest: true,
    visited: visited,
  );
  final snapshot = TacticalMapSnapshot(
    xStart: 0,
    yStart: 0,
    floor: 0,
    cells: [cell],
    location: 'Synthetic combined-status fixture',
    currentDescription: '',
    alarm: '',
    cameras: false,
    response: '',
    columnCount: 1,
    rowCount: 1,
  );
  TacticalMapPainter(snapshot, art: art).paint(canvas, const Size(32, 32));
});

void main() {
  setUpAll(ensureGameDataLoaded);

  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    game.siteAlarm = false;
    game.siteAlarmTimer = -1;
    game.postAlarmTimer = 0;
    game.activeSite = Site(SiteType.courthouse);
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
  });

  test('supplemental provenance and runtime crops stay synchronized', () async {
    const expectedCells = [
      ('detention_cell', TacticalObjectCell.detentionCell),
      ('patient_bed', TacticalObjectCell.nursingBed),
      ('executive_desk', TacticalObjectCell.executiveDesk),
      ('presidential_desk', TacticalObjectCell.presidentialDesk),
      ('bank_teller_counter', TacticalObjectCell.tellerCounter),
      ('bank_vault_door', TacticalObjectCell.bankVault),
      ('jury_table', TacticalObjectCell.juryTable),
      ('blank_signboard', TacticalObjectCell.signboard),
      ('tv_camera', TacticalObjectCell.tvCamera),
      ('server_rack', TacticalObjectCell.serverRack),
      ('textile_workbench', TacticalObjectCell.sewingMachine),
      ('reactor_console', TacticalObjectCell.reactorConsole),
      ('armory_rack', TacticalObjectCell.weaponRack),
      ('security_console', TacticalObjectCell.prisonConsole),
      ('manager_desk', TacticalObjectCell.officeDesk),
      ('claims_terminal', TacticalObjectCell.claimsTerminal),
    ];
    final metadata =
        jsonDecode(
              await File(
                '../assets/tactical/supplemental-prompts.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final cells = metadata['cells'] as List<dynamic>;
    final crops = tacticalExtraObjectAtlas.normalizedCrops;
    expect(crops, isNotNull);
    expect(crops, hasLength(16));
    expect(cells, hasLength(16));
    for (var index = 0; index < expectedCells.length; index++) {
      final cell = cells[index] as Map<String, dynamic>;
      expect(cell['index'], index);
      expect(cell['key'], expectedCells[index].$1);
      expect(expectedCells[index].$2, 16 + index);
      final recorded = (cell['sourceRectNormalized'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList();
      final runtime = crops![index];
      final actual = [runtime.left, runtime.top, runtime.width, runtime.height];
      expect(recorded, hasLength(actual.length));
      for (var coordinate = 0; coordinate < actual.length; coordinate++) {
        expect(
          actual[coordinate],
          closeTo(recorded[coordinate], 1e-8),
          reason: '${expectedCells[index].$1}, coordinate $coordinate',
        );
      }
    }
  });

  test('every requested room state is illustrated in local and full maps', () {
    final tile = levelMap[36][11][0]
      ..known = true
      ..inLOS = true;
    for (final (special, sprite) in _scope) {
      tile.special = special;
      for (final fullMap in [false, true]) {
        final captured = _cell(TacticalMapSnapshot.capture(fullMap: fullMap));
        expect(captured.objectSprite, sprite, reason: special.name);
        expect(captured.kind, TacticalTileKind.special, reason: special.name);
        expect(captured.pointOfInterest, isTrue, reason: special.name);
        expect(captured.actionHint, isNotEmpty, reason: special.name);
        expect(
          captured.visited,
          special == TileSpecial.nursingHomePatientDone,
          reason: special.name,
        );
        expect(captured.objectQuadrant, switch (special) {
          TileSpecial.ovalOfficeNW => 0,
          TileSpecial.ovalOfficeNE => 1,
          TileSpecial.ovalOfficeSW => 2,
          TileSpecial.ovalOfficeSE => 3,
          _ => null,
        }, reason: special.name);
      }
    }
    expect(_scope.map((entry) => entry.$2).toSet().length, 16);
  });

  test('all requested room states remain secret until explored', () {
    final tile = levelMap[36][11][0]
      ..inLOS = true
      ..restricted = true
      ..firePeak = true
      ..siegeHeavyUnit = true;
    for (final (special, _) in _scope) {
      tile.special = special;
      for (final fullMap in [false, true]) {
        final captured = _cell(TacticalMapSnapshot.capture(fullMap: fullMap));
        expect(captured.kind, TacticalTileKind.unknown, reason: special.name);
        expect(captured.semanticLabel, 'Unexplored', reason: special.name);
        expect(captured.objectSprite, isNull, reason: special.name);
        expect(captured.hazardSprite, isNull, reason: special.name);
        expect(captured.underlyingKind, isNull, reason: special.name);
        expect(captured.actionHint, isEmpty, reason: special.name);
        expect(captured.pointOfInterest, isFalse, reason: special.name);
        expect(captured.visited, isFalse, reason: special.name);
        expect(captured.graffiti, isNull, reason: special.name);
        expect(captured.objectQuadrant, isNull, reason: special.name);
      }
    }
  });

  test('graffiti respects known neighbors and original wall precedence', () {
    final wall = levelMap[36][11][0]
      ..known = true
      ..inLOS = true
      ..wall = true;
    final marked = levelMap[37][11][0]
      ..graffitiLCS = true
      ..graffitiCCS = true
      ..graffitiOther = true;
    for (final fullMap in [false, true]) {
      expect(
        _cell(TacticalMapSnapshot.capture(fullMap: fullMap)).graffiti,
        isNull,
        reason: 'Unexplored adjacent markings must not decorate a known wall.',
      );
    }
    marked.known = true;
    expect(_cell(TacticalMapSnapshot.capture()).graffiti, TacticalGraffiti.lcs);
    marked.graffitiLCS = false;
    expect(_cell(TacticalMapSnapshot.capture()).graffiti, TacticalGraffiti.ccs);
    marked.graffitiCCS = false;
    expect(
      _cell(TacticalMapSnapshot.capture()).graffiti,
      TacticalGraffiti.other,
    );
    marked.megaBloody = true;
    var captured = _cell(TacticalMapSnapshot.capture());
    expect(captured.label, 'Bloodstained wall');
    expect(captured.graffiti, isNull);
    wall.firePeak = true;
    captured = _cell(TacticalMapSnapshot.capture());
    expect(captured.label, 'Burning wall');
    expect(captured.graffiti, isNull);
    expect(captured.hazardSprite, TacticalHazardCell.intenseFire);
  });

  test('supplemental room art preserves foreground and inspection purity', () {
    final tile = levelMap[36][11][0]
      ..known = true
      ..inLOS = true
      ..restricted = true
      ..firePeak = true
      ..siegeHeavyUnit = true;
    for (final (special, sprite) in _scope) {
      tile.special = special;
      final before = _state();
      reseedRNG(seed: 482217);
      final expected = lcsRandom(1000000);
      reseedRNG(seed: 482217);
      final cell = _cell(TacticalMapSnapshot.capture());
      expect(cell.kind, TacticalTileKind.armoredEnemy, reason: special.name);
      expect(cell.objectSprite, sprite, reason: special.name);
      expect(cell.hazardSprite, TacticalHazardCell.intenseFire);
      expect(cell.semanticLabel, contains('Armored enemy'));
      expect(cell.semanticLabel, contains('Restricted area'));
      expect(cell.semanticLabel, contains('Intense fire'));
      expect(cell.underlyingKind, TacticalTileKind.special);
      expect(_state(), before);
      expect(lcsRandom(1000000), expected);
    }
  });

  testWidgets('real supplemental art survives a shared-cache map journey', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 700);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    levelMap[36][11][0]
      ..known = true
      ..inLOS = true
      ..special = TileSpecial.bankVault;
    final before = _state();
    final moves = <String>[];
    Widget app(Widget child, {double scale = 1}) => MaterialApp(
      theme: buildJournalTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(app(TacticalMapView(onMove: moves.add)));
    final errors = <Object>[];
    await tester.runAsync(() async {
      final context = tester.element(find.byType(TacticalMapView));
      await Future.wait([
        for (final atlas in [
          tacticalTerrainAtlas,
          tacticalObjectAtlas,
          tacticalHazardAtlas,
          tacticalExtraObjectAtlas,
        ])
          precacheImage(
            AssetImage(atlas.asset),
            context,
            onError: (error, stack) => errors.add(error),
          ),
      ]);
    });
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
    final local =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('tactical-map-grid')),
                )
                .painter!
            as TacticalMapPainter;
    expect(local.art, isNotNull);
    expect(local.art!.extraObjects.width, greaterThan(0));
    final extraWidth = local.art!.extraObjects.width;
    final sprites = await tester.runAsync(
      () async => [
        for (var index = 16; index < 32; index++)
          await _spritePixels(local.art!, index),
      ],
    );
    for (var i = 0; i < sprites!.length; i++) {
      expect(sprites[i].length, 32 * 32 * 4);
      expect(
        [
          for (var p = 3; p < sprites[i].length; p += 4) sprites[i][p],
        ].any((alpha) => alpha > 0),
        isTrue,
        reason: 'Supplemental cell $i must paint at native map scale.',
      );
      for (var j = 0; j < i; j++) {
        expect(
          sprites[i],
          isNot(sprites[j]),
          reason: 'Supplemental cells $i and $j must not repeat one painting.',
        );
      }
    }
    await tester.runAsync(() async {
      final wholeDesk = await _paintPixels(
        64,
        (canvas) => local.art!.drawObject(
          canvas,
          const Rect.fromLTWH(0, 0, 64, 64),
          TacticalObjectCell.presidentialDesk,
        ),
      );
      final assembledDesk = await _paintPixels(64, (canvas) {
        for (var quadrant = 0; quadrant < 4; quadrant++) {
          local.art!.drawObject(
            canvas,
            Rect.fromLTWH((quadrant % 2) * 32, (quadrant ~/ 2) * 32, 32, 32),
            TacticalObjectCell.presidentialDesk,
            quadrant: quadrant,
          );
        }
      });
      // Raster filtering may differ on the one-pixel internal crop boundary.
      // Every interior pixel must still reconstruct the single full painting.
      for (var y = 1; y < 63; y++) {
        if (y == 31 || y == 32) continue;
        for (var x = 1; x < 63; x++) {
          if (x == 31 || x == 32) continue;
          for (var channel = 0; channel < 4; channel++) {
            final offset = (y * 64 + x) * 4 + channel;
            expect(
              (wholeDesk[offset] - assembledDesk[offset]).abs(),
              lessThanOrEqualTo(2),
              reason: 'The Oval Office must form one desk, not four repeats.',
            );
          }
        }
      }
      for (final trap in [false, true]) {
        final plain = await _combinedStatusPixels(
          local.art!,
          visited: false,
          trap: trap,
        );
        final visited = await _combinedStatusPixels(
          local.art!,
          visited: true,
          trap: trap,
        );
        expect(visited, isNot(plain));
        for (var y = 0; y < 12; y++) {
          for (var x = 0; x < 12; x++) {
            final offset = (y * 32 + x) * 4;
            expect(
              visited.sublist(offset, offset + 4),
              plain.sublist(offset, offset + 4),
              reason:
                  'Visited status must leave the occupied fire badge clear.',
            );
          }
        }
      }
    });
    await tester.tap(find.byKey(const ValueKey('field-plan-key-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('field-plan-key-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('field-plan-key-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      app(
        const Center(
          child: SizedBox(
            width: 560,
            height: 400,
            child: FullSiteMap(showHeading: false),
          ),
        ),
        scale: 1.5,
      ),
    );
    await tester.pumpAndSettle();
    final full =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('full-site-map-grid')),
                )
                .painter!
            as TacticalMapPainter;
    expect(full.art, isNotNull);
    expect(full.art!.extraObjects.width, extraWidth);
    expect(_cell(full.snapshot).objectSprite, TacticalObjectCell.bankVault);
    expect(full.onMove, isNull);
    expect(_state(), before);
    expect(moves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
