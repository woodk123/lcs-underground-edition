import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/money.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/catalogue_art.dart';
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

// Independent QA: deliberately prepared presentation fixtures, not earned loot.
const _capture = ValueKey('tactical-loot-independent-qa');

TacticalMapCell _cell(TacticalMapSnapshot snapshot, [int x = 35, int y = 11]) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

String _state() => jsonEncode({
  'game': game.gameState.toJson(),
  'location': [game.locx, game.locy, game.locz],
  'tiles': [
    for (final tile in levelMap.all)
      [tile.flag, tile.siegeflag, tile.inLOS, tile.special.name],
  ],
});

Future<void> _captureScreen(WidgetTester tester, String name) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('../reports/tactical-loot-independent-qa');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await ensureGameDataLoaded();
    for (final (family, path) in [
      ('JournalSerif', 'fonts/journal/LibreBaskerville-Variable.ttf'),
      ('ModernSans', 'fonts/modern/roboto-regular.ttf'),
      ('Roboto', 'fonts/modern/roboto-regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    doorInteractionOrigin = null;
    game.siteAlarmTimer = -1;
    game.activeSite = Site(SiteType.courthouse);
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    for (var x = 27; x < 44; x++) {
      for (var y = 8; y < 15; y++) {
        levelMap[x][y][0]
          ..known = true
          ..inLOS = true;
      }
    }
  });
  tearDown(() => doorInteractionOrigin = null);

  test('QA: no rolled contents or hidden piles leak in either map', () {
    game.groundLoot.add(Loot('LOOT_WATCH', stackSize: 3));
    levelMap[36][11][0].loot = true;
    for (final full in [false, true]) {
      final snapshot = TacticalMapSnapshot.capture(fullMap: full);
      final unsearched = _cell(snapshot, 36);
      expect(unsearched.unsearchedLoot, isTrue);
      expect(unsearched.droppedItems, isEmpty);
      expect(unsearched.lootArtwork, isNull);
      expect(unsearched.lootSummary, 'Unsearched loot');
      expect(_cell(snapshot).droppedItems.single.quantity, 3);
      expect(
        snapshot.cells.where((cell) => cell.droppedItems.isNotEmpty),
        hasLength(1),
      );
    }
    levelMap[35][11][0].known = false;
    for (final full in [false, true]) {
      final hidden = _cell(TacticalMapSnapshot.capture(fullMap: full));
      expect(hidden.semanticLabel, 'Unexplored');
      expect(hidden.droppedItems, isEmpty);
      expect(hidden.lootArtwork, isNull);
    }
  });

  test(
    'QA: snapshots freeze real conditions, quantity and cash without RNG',
    () {
      final first = Clothing('CLOTHING_CLOTHES')..bloody = true;
      final second = Clothing('CLOTHING_CLOTHES');
      game.groundLoot.addAll([
        first,
        second,
        Money(500),
        Loot('LOOT_WATCH', stackSize: 0),
      ]);
      final before = _state();
      nextRngSeed = 91017;
      final expected = List.generate(8, (_) => lcsRandom(100000));
      nextRngSeed = 91017;
      final snapshot = TacticalMapSnapshot.capture();
      final pile = _cell(snapshot);
      expect(pile.droppedItems, hasLength(3));
      expect(pile.lootArtwork, isNull);
      expect(pile.droppedItems[0].title, first.equipTitle());
      expect(pile.droppedItems[1].title, second.equipTitle());
      expect(pile.droppedItems[0].title, isNot(pile.droppedItems[1].title));
      expect(pile.droppedItems[2].label, r'$500');
      expect(pile.lootSummary, 'Dropped loot: 3 stacks');
      expect(pile.droppedItems.clear, throwsUnsupportedError);
      expect(_state(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
      first.bloody = false;
      game.groundLoot.clear();
      expect(pile.droppedItems[0].title, isNot(first.equipTitle()));
      expect(pile.droppedItems, hasLength(3));
      expect(_cell(TacticalMapSnapshot.capture()).droppedItems, isEmpty);
    },
  );

  test('QA: standing squad keeps drops during temporary door coordinates', () {
    game.groundLoot.add(Loot('LOOT_WATCH'));
    doorInteractionOrigin = (x: 35, y: 11, z: 0);
    game.locx = 36;
    levelMap[36][11][0].door = true;
    final snapshot = TacticalMapSnapshot.capture();
    expect(_cell(snapshot).droppedItems, hasLength(1));
    expect(_cell(snapshot, 36).droppedItems, isEmpty);
    expect(
      _cell(snapshot).lootArtwork!.source,
      equipmentArtwork('LOOT_WATCH')!.source,
    );
    levelMap[35][11][0].loot = true;
    expect(
      _cell(TacticalMapSnapshot.capture()).lootArtwork,
      isNull,
      reason: 'Known drops cannot disguise an additional unsearched cache.',
    );
  });

  testWidgets(
    'QA: production maps and item details remain usable at supported sizes',
    (tester) async {
      final moves = <String>[];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      Widget app(Widget child, double scale) => RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );
      Future<void> settle() async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      game.groundLoot.add(Loot('LOOT_WATCH', stackSize: 3));
      final before = _state();
      nextRngSeed = 1008;
      final expected = List.generate(8, (_) => lcsRandom(100000));
      nextRngSeed = 1008;
      for (final (size, scale, name) in [
        (const Size(1280, 800), 1.0, 'desktop'),
        (const Size(800, 600), 1.5, 'compact-150'),
        (const Size(360, 640), 2.0, 'narrow-200'),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          app(
            size.width < 400
                ? SizedBox(
                    height: 340,
                    child: TacticalMapView(
                      onMove: moves.add,
                      showHeading: false,
                    ),
                  )
                : TacticalMapView(onMove: moves.add),
            scale,
          ),
        );
        await settle();
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('tactical-map-grid')),
                    )
                    .painter!
                as TacticalMapPainter;
        expect(painter.art?.lootImage, isNotNull);
        expect(_cell(painter.snapshot).lootArtwork, isNotNull);
        await _captureScreen(tester, 'local-single-$name');
        await tester.tap(find.byKey(const ValueKey('tactical-tile-details')));
        await settle();
        expect(find.text('Dropped here'), findsOneWidget);
        expect(find.text('Watch ×3'), findsOneWidget);
        expect(find.byType(CatalogueIllustration), findsOneWidget);
        await tester.ensureVisible(find.text('Watch ×3'));
        await settle();
        await _captureScreen(tester, 'details-single-$name');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle();
        expect(find.text('Dropped here'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('tactical-tile-details')));
        await settle();
        await tester.tap(find.text('Close tile details'));
        await settle();
        expect(_state(), before);
      }
      expect(moves, isEmpty);
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpWidget(app(TacticalMapView(onMove: moves.add), 1.5));
      await settle();
      await tester.tap(find.byKey(const ValueKey('tactical-zoom-in')));
      await settle();
      await tester.tap(find.byKey(const ValueKey('tactical-inspect-mode')));
      await settle();
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final retainedZoom = controller.value.clone();
      game.groundLoot.addAll([Loot('LOOT_FAMILYPHOTO'), Money(500)]);
      await tester.pumpWidget(app(TacticalMapView(onMove: moves.add), 1.5));
      await settle();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController,
        same(controller),
      );
      expect(controller.value, retainedZoom);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('tactical-inspect-mode')),
            )
            .selected,
        isTrue,
      );
      await _captureScreen(tester, 'local-mixed-compact-150');
      await tester.tap(find.byKey(const ValueKey('tactical-tile-details')));
      await settle();
      expect(find.text(r'$500'), findsOneWidget);
      expect(find.byType(CatalogueIllustration), findsNWidgets(2));
      await tester.ensureVisible(find.text(r'$500'));
      await settle();
      await _captureScreen(tester, 'details-mixed-compact-150');
      await tester.tap(find.text('Close tile details'));
      await settle();
      await tester.pumpWidget(app(const FullSiteMap(showHeading: false), 1.5));
      await settle();
      final full =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('full-site-map-grid')),
                  )
                  .painter!
              as TacticalMapPainter;
      expect(full.onMove, isNull);
      expect(_cell(full.snapshot).droppedItems, hasLength(3));
      await tester.tap(find.byKey(const ValueKey('full-map-find-squad')));
      await settle();
      await _captureScreen(tester, 'full-mixed-compact-150');
      await tester.tap(find.byKey(const ValueKey('tactical-tile-details')));
      await settle();
      await tester.ensureVisible(find.text(r'$500'));
      await settle();
      await _captureScreen(tester, 'full-details-mixed-compact-150');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
      levelMap[35][11][0]
        ..special = TileSpecial.ceoSafe
        ..firePeak = true
        ..siegeTrap = true;
      await tester.pumpWidget(app(TacticalMapView(onMove: moves.add), 1.5));
      await settle();
      await _captureScreen(
        tester,
        'combined-fixture-fire-trap-mixed-compact-150',
      );
      await tester.tap(find.byKey(const ValueKey('tactical-tile-details')));
      await settle();
      await _captureScreen(
        tester,
        'combined-details-fixture-fire-trap-mixed-compact-150',
      );
      expect(find.textContaining('Defensive boobytrap'), findsWidgets);
      expect(find.textContaining('Intense fire'), findsWidgets);
      expect(moves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
