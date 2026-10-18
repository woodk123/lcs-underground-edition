import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/item_help_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/item_type.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/catalogue_art.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/shop.dart' show ShopUI, shopTypes;
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

String _painting(CatalogueArtEntry art) => '${art.asset}:${art.source}';

List<Map<String, dynamic>> _jsonRecords(Object? value) =>
    (value! as List<dynamic>).cast<Map<String, dynamic>>();

Future<void> _settleCataloguePaintings(WidgetTester tester) async {
  // Native image codecs complete outside Flutter's fake clock. Require the
  // actual production painters before treating a layout/capture as reviewed.
  final illustrations = find.byType(CatalogueIllustration);
  final painters = find.descendant(
    of: illustrations,
    matching: find.byType(CustomPaint),
  );
  for (var attempt = 0; attempt < 100; attempt++) {
    if (painters.evaluate().length == illustrations.evaluate().length) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(painters.evaluate().length, illustrations.evaluate().length);
}

Future<void> _warmCatalogueAtlases(WidgetTester tester) async {
  // Keep every shared native-image future inside a live test zone until it has
  // decoded, as the application does during its single cache lifetime.
  await tester.pumpWidget(
    MaterialApp(
      theme: buildJournalTheme(),
      home: Row(
        children: [
          CatalogueIllustration(art: equipmentArtwork('WEAPON_9MM_HANDGUN')!),
          CatalogueIllustration(art: equipmentArtwork('CLOTHING_CLOTHES')!),
          CatalogueIllustration(art: vehicleArtwork('BUG')!),
        ],
      ),
    ),
  );
  await _settleCataloguePaintings(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String campaignFixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    campaignFixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await Future.wait([serif.load(), sans.load()]);
  });
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(campaignFixture).gameState!;
  });

  test(
    'catalogue artwork covers real equipment and every distinct vehicle',
    () {
      final equipment = <CatalogueArtEntry>[
        for (final id in itemTypes.keys)
          if (equipmentArtwork(id) case final art?) art,
      ];
      expect(equipment.map(_painting).toSet(), hasLength(32));
      expect(vehicleTypes, hasLength(11));
      final vehicles = <CatalogueArtEntry>[];
      for (final id in vehicleTypes.keys) {
        final art = vehicleArtwork(id);
        expect(art, isNotNull, reason: id);
        vehicles.add(art!);
      }
      expect(vehicles.map(_painting).toSet(), hasLength(11));
      for (final unsupported in [
        '',
        'UNRECOGNIZED_CATALOGUE_ITEM',
        'WEAPON_NONE',
        'CLOTHING_NONE',
        'BUG',
      ]) {
        expect(equipmentArtwork(unsupported), isNull, reason: unsupported);
      }
      expect(vehicleArtwork('WEAPON_9MM_HANDGUN'), isNull);
      expect(vehicleArtwork('UNRECOGNIZED_CATALOGUE_VEHICLE'), isNull);
    },
  );

  test('art resolution preserves the complete campaign and random stream', () {
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 70913);
    final rolls = List.generate(20, (_) => lcsRandom(100000));
    reseedRNG(seed: 70913);
    for (var repeat = 0; repeat < 3; repeat++) {
      for (final id in itemTypes.keys) {
        equipmentArtwork(id);
      }
      for (final id in vehicleTypes.keys) {
        vehicleArtwork(id);
      }
    }
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(List.generate(20, (_) => lcsRandom(100000)), rolls);
  });

  test('type previews are isolated to exact original choices without RNG', () {
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 52291);
    final rolls = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 52291);
    engine.addOptionText(
      10,
      1,
      'a',
      'A - Catalogue weapon',
      enabledWhen: false,
    );
    final first = engine.console.actions.single;
    describeChoiceItemType(engine.console, 'A', 'WEAPON_9MM_HANDGUN');
    expect(choiceItemTypeId(first), 'WEAPON_9MM_HANDGUN');
    expect(choiceItem(first), isNull);
    expect(first.enabled, isFalse);
    engine.erase();
    engine.addOptionText(10, 1, 'a', 'A - Catalogue vehicle');
    final replacement = engine.console.actions.single;
    expect(choiceItemTypeId(replacement), isNull);
    describeChoiceVehicleType(engine.console, 'A', 'BUG');
    expect(choiceVehicleTypeId(replacement), 'BUG');
    expect(choiceVehicle(replacement), isNull);
    expect(choiceVehicleTypeId(first), isNull);
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
  });

  test('passenger a and driver A keep separate exact vehicle metadata', () {
    engine.addOptionText(10, 1, 'a', 'a - Passenger');
    engine.console.addAction('A', 'A - Drive', caseSensitive: true);
    final passenger = engine.console.actions.singleWhere((a) => a.key == 'a');
    final driver = engine.console.actions.singleWhere((a) => a.key == 'A');
    describeChoiceVehicleType(engine.console, 'a', 'BUG');
    describeChoiceVehicleType(engine.console, 'A', 'JEEP');
    expect(choiceVehicleTypeId(passenger), 'BUG');
    expect(choiceVehicleTypeId(driver), 'JEEP');
    final passengerCar = Vehicle('PICKUP');
    final driverCar = Vehicle('VAN');
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 40819);
    final rolls = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 40819);
    describeChoiceVehicle(engine.console, 'a', passengerCar);
    describeChoiceVehicle(engine.console, 'A', driverCar);
    expect(choiceVehicle(passenger), same(passengerCar));
    expect(choiceVehicle(driver), same(driverCar));
    expect(choiceVehicleTypeId(passenger), 'PICKUP');
    expect(choiceVehicleTypeId(driver), 'VAN');
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
  });

  test(
    'legacy saved equipment resolves artwork through the canonical type',
    () {
      final weapon = game.pool.first.equippedWeapon!;
      expect(weapon.typeName, 'WEAPON_AUTORIFLE_AK47');
      expect(weapon.type.idName, 'WEAPON_AK102');
      final before = jsonEncode(game.gameState.toJson());
      engine.addOptionText(10, 1, 'a', 'a - ${weapon.type.name}');
      describeChoiceItem(engine.console, 'a', weapon);
      final action = engine.console.actions.single;
      expect(choiceItemTypeId(action), weapon.type.idName);
      expect(equipmentArtwork(choiceItemTypeId(action)), isNotNull);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(weapon.typeName, 'WEAPON_AUTORIFLE_AK47');
    },
  );

  test('full catalogue descriptions cannot survive a replaced reader', () {
    engine.addOptionText(10, 1, 'a', 'a - .22 Revolver');
    describeChoiceItemDescription(
      engine.console,
      'a',
      11,
      'A whole description.',
    );
    expect(choiceItemDescription(engine.console, 11), 'A whole description.');
    engine.erase();
    engine.addOptionText(10, 1, 'a', 'a - Different product');
    expect(choiceItemDescription(engine.console, 11), isNull);
  });

  test(
    'provenance matches every live crop and validated manifest hash',
    () async {
      final provenance =
          jsonDecode(
                await File(
                  '../assets/catalogue/provenance.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final manifest =
          jsonDecode(
                await File(
                  '../assets/runtime-art/manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final records = <String, Map<String, dynamic>>{
        for (final record in _jsonRecords(manifest['assets']))
          record['runtime_path'] as String: record,
      };
      expect(provenance['equipment_paintings'], 32);
      expect(provenance['vehicle_paintings'], 11);
      final declaredIds = <String>{};
      for (final asset in _jsonRecords(provenance['assets'])) {
        final runtimePath = asset['runtime_path'] as String;
        final record = records[runtimePath]!;
        expect(asset['source_path'], record['original_path']);
        expect(asset['source_sha256'], record['original_sha256']);
        expect(asset['runtime_sha256'], record['runtime_sha256']);
        expect(asset['width'], record['width']);
        expect(asset['height'], record['height']);
        expect(File('../${asset['prompt_path']}').existsSync(), isTrue);
        for (final entry in _jsonRecords(asset['entries'])) {
          final id = entry['type_id'] as String;
          expect(declaredIds.add(id), isTrue, reason: id);
          expect(
            itemTypes.containsKey(id) || vehicleTypes.containsKey(id),
            isTrue,
          );
          final art = equipmentArtwork(id) ?? vehicleArtwork(id);
          expect(art, isNotNull, reason: id);
          expect(art!.asset, runtimePath.substring('upstream/'.length));
          expect(
            [
              art.source.left,
              art.source.top,
              art.source.width,
              art.source.height,
            ],
            entry['source_rect'],
            reason: id,
          );
        }
      }
      expect(declaredIds, hasLength(43));
    },
  );

  test(
    'every selected painting has unclipped transparent source edges',
    () async {
      final manifest =
          jsonDecode(
                await File(
                  '../assets/runtime-art/manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final sources = <String, String>{
        for (final raw in _jsonRecords(manifest['assets']))
          (raw['runtime_path'] as String).substring('upstream/'.length):
              raw['original_path'] as String,
      };
      final unique = <String, CatalogueArtEntry>{};
      for (final id in itemTypes.keys) {
        if (equipmentArtwork(id) case final art?) unique[_painting(art)] = art;
      }
      for (final id in vehicleTypes.keys) {
        if (vehicleArtwork(id) case final art?) unique[_painting(art)] = art;
      }
      final images = <String, ui.Image>{};
      final pixels = <String, ByteData>{};
      try {
        for (final art in unique.values) {
          if (!images.containsKey(art.asset)) {
            expect(sources, contains(art.asset));
            final codec = await ui.instantiateImageCodec(
              await File('../${sources[art.asset]}').readAsBytes(),
            );
            final image = (await codec.getNextFrame()).image;
            codec.dispose();
            images[art.asset] = image;
            pixels[art.asset] = (await image.toByteData())!;
          }
          final image = images[art.asset]!;
          final rgba = pixels[art.asset]!.buffer.asUint8List();
          final rect = art.source;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(image.width));
          expect(rect.bottom, lessThanOrEqualTo(image.height));
          expect(rect.width, greaterThan(0));
          expect(rect.height, greaterThan(0));
          final left = rect.left.ceil();
          final top = rect.top.ceil();
          final right = rect.right.floor() - 1;
          final bottom = rect.bottom.floor() - 1;
          int alpha(int x, int y) => rgba[(y * image.width + x) * 4 + 3];
          var clipped = 0;
          for (var x = left; x <= right; x++) {
            if (alpha(x, top) > 10) clipped++;
            if (alpha(x, bottom) > 10) clipped++;
          }
          for (var y = top; y <= bottom; y++) {
            if (alpha(left, y) > 10) clipped++;
            if (alpha(right, y) > 10) clipped++;
          }
          expect(clipped, 0, reason: _painting(art));
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  testWidgets(
    'all illustrated choices and guides share one live cache lifetime',
    (tester) async {
      await _warmCatalogueAtlases(tester);
      for (final sizeAndScale in [
        (const Size(1280, 800), 1.0),
        (const Size(800, 600), 1.5),
        (const Size(360, 640), 2.0),
      ]) {
        {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = sizeAndScale.$1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final sent = <String>[];
          for (final enabled in [true, false]) {
            engine.erase();
            engine.addOptionText(
              10,
              1,
              'a',
              'A - 9mm Pistol (2) — \$1234',
              enabledWhen: enabled,
            );
            describeChoiceItemType(engine.console, 'a', 'WEAPON_9MM_HANDGUN');
            await tester.pumpWidget(
              MaterialApp(
                theme: buildJournalTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(sizeAndScale.$2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: DirectContent(
                      console: engine.console,
                      onAction: sent.add,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await _settleCataloguePaintings(tester);
            expect(find.byType(CatalogueIllustration), findsOneWidget);
            final callsBefore = sent.length;
            await tester.tapAt(
              tester.getCenter(find.byType(CatalogueIllustration)),
            );
            await tester.pumpAndSettle();
            expect(sent.length, callsBefore + (enabled ? 1 : 0));
            if (enabled) expect(sent.last, 'a');
            expect(tester.takeException(), isNull);
          }
        }

        {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = sizeAndScale.$1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final reader = engine.console.getkey();
          final before = jsonEncode(game.gameState.toJson());
          reseedRNG(seed: 95104);
          final rolls = List.generate(12, (_) => lcsRandom(100000));
          reseedRNG(seed: 95104);
          for (final selection in [
            (DecisionTopic.weapons, 'WEAPON_9MM_HANDGUN'),
            (DecisionTopic.clothing, 'CLOTHING_CLOTHES'),
            (DecisionTopic.vehicles, 'BUG'),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildJournalTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(sizeAndScale.$2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: DecisionGuideButton(
                      topic: selection.$1,
                      itemType: selection.$2,
                      actor: game.pool.first,
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.byType(TextButton));
            await tester.pumpAndSettle();
            await _settleCataloguePaintings(tester);
            expect(find.byType(CatalogueIllustration), findsWidgets);
            final expectedArt = selection.$1 == DecisionTopic.vehicles
                ? vehicleArtwork(selection.$2)!
                : equipmentArtwork(selection.$2)!;
            expect(
              tester
                  .widgetList<CatalogueIllustration>(
                    find.byType(CatalogueIllustration),
                  )
                  .any(
                    (widget) => _painting(widget.art) == _painting(expectedArt),
                  ),
              isTrue,
              reason:
                  'The selected catalogue identity must choose its own art.',
            );
            expect(
              find.byTooltip('Close decision guide').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            expect(engine.console.awaitingInput, isTrue);
            expect(jsonEncode(game.gameState.toJson()), before);
            await tester.tap(find.byTooltip('Close decision guide'));
            await tester.pumpAndSettle();
          }
          expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
          engine.console.sendInput('Enter');
          await tester.pump();
          await reader;
        }
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final paintings = <String, (String, CatalogueArtEntry)>{};
      for (final entry in itemTypes.entries) {
        if (equipmentArtwork(entry.key) case final art?) {
          paintings.putIfAbsent(_painting(art), () => (entry.value.name, art));
        }
      }
      for (final entry in vehicleTypes.entries) {
        if (vehicleArtwork(entry.key) case final art?) {
          paintings.putIfAbsent(
            _painting(art),
            () => (entry.value.longName, art),
          );
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: RepaintBoundary(
            key: const ValueKey('catalogue-qa-capture'),
            child: Scaffold(
              backgroundColor: JournalPalette.page,
              body: Wrap(
                children: [
                  for (final painting in paintings.values)
                    SizedBox(
                      width: 260,
                      height: 165,
                      child: Column(
                        children: [
                          Text(painting.$1),
                          CatalogueIllustration(art: painting.$2),
                          CatalogueIllustration(
                            art: painting.$2,
                            width: 168,
                            height: 90,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _settleCataloguePaintings(tester);
      expect(tester.takeException(), isNull);
      if (Platform.environment['LCS_CAPTURE_SCREENS'] != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('catalogue-qa-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(
            '../reports/catalogue-art-qa',
          ).create(recursive: true);
          await File(
            '../reports/catalogue-art-qa/runtime-contact-sheet.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> sourceCapture(String name) async {
        if (Platform.environment['LCS_CAPTURE_SCREENS'] == null) return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('catalogue-source-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../reports/catalogue-art-qa/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> sourceAction(String key) async {
        final action = engine.console.actions.singleWhere(
          (a) => a.key == key && a.enabled,
        );
        final button = find.byKey(
          ValueKey('direct-action:${action.y}:${action.x}:${action.key}'),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await _settleCataloguePaintings(tester);
        expect(tester.takeException(), isNull);
      }

      Future<void> sourceFlow(
        Future<void> Function() run,
        Future<void> Function() interact,
      ) async {
        await tester.pumpWidget(const SizedBox.shrink());
        var finished = false;
        Object? failure;
        final flow = run().then(
          (_) => finished = true,
          onError: (Object error) {
            failure = error;
            finished = true;
          },
        );
        try {
          await tester.pumpWidget(
            const RepaintBoundary(
              key: ValueKey('catalogue-source-capture'),
              child: MainApp(),
            ),
          );
          await tester.pumpAndSettle();
          await _settleCataloguePaintings(tester);
          expect(engine.console.awaitingInput, isTrue);
          expect(tester.takeException(), isNull);
          await interact();
          expect(finished, isTrue);
          expect(failure, isNull);
        } finally {
          for (var attempt = 0; attempt < 12 && !finished; attempt++) {
            if (engine.console.awaitingInput) {
              engine.console.sendInput('Escape');
            }
            await tester.pump(const Duration(milliseconds: 10));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          if (finished) await flow;
        }
      }

      // Actual source handlers with explicitly prepared funds. Purchases use
      // their original readers, prices and callbacks; no outcomes are mocked.
      for (final (size, scale, name) in [
        (const Size(1280, 800), 1.0, 'desktop'),
        (const Size(800, 600), 1.5, 'large'),
      ]) {
        tester.view.physicalSize = size;
        journalReadingScale.value = scale;
        game.gameState = decodeSaveContents(campaignFixture).gameState!;
        game.mode = GameMode.base;
        game.activeSquadMember = null;
        engine.console = Console();
        game.ledger.forceSetFunds(1000000);
        final department = shopTypes['PAWNSHOP']!.departments.firstWhere(
          (shop) => shop.ui == ShopUI.weapons,
        );
        final product = department.items.where((item) => item.display()).first;
        final buyer = game.squad.first;
        await sourceFlow(() => department.enter(game.activeSquad!), () async {
          expect(find.byType(CatalogueIllustration), findsWidgets);
          final first = engine.console.actions.singleWhere((a) => a.key == 'a');
          expect(choiceItemTypeId(first), product.itemId);
          final description = weaponTypes[product.itemId]!.description!;
          expect(
            choiceItemDescription(engine.console, first.y + 1),
            description,
          );
          expect(find.text(description), findsOneWidget);
          await sourceCapture('$name-source-weapon-shop');
          await sourceAction('a');
          expect(buyer.weapon.type.idName, product.itemId);
          expect(game.ledger.funds, 1000000 - product.price(false));
          engine.console.sendInput('Escape');
          await tester.pumpAndSettle();
        });
        engine.console = Console();
        game.vehiclePool.clear();
        for (final person in game.squad) {
          person.preferredCarId = null;
        }
        game.ledger.forceSetFunds(1000000);
        final carType = vehicleTypes.values.firstWhere(
          (v) => v.availableAtDealership,
        );
        await sourceFlow(() => dealership(game.activeSquad!.site!), () async {
          await sourceAction('g');
          expect(find.byType(CatalogueIllustration), findsWidgets);
          final first = engine.console.actions.singleWhere((a) => a.key == 'a');
          expect(choiceVehicleTypeId(first), carType.idName);
          await tester.ensureVisible(
            find.byKey(
              ValueKey('direct-action:${first.y}:${first.x}:${first.key}'),
            ),
          );
          await tester.pumpAndSettle();
          await sourceCapture('$name-source-dealership');
          await sourceAction('a');
          await sourceAction('a');
          expect(game.vehiclePool.single.typeName, carType.idName);
          expect(game.squad.first.preferredCarId, game.vehiclePool.single.id);
          expect(game.ledger.funds, 1000000 - carType.price);
          await sourceAction('Enter');
        });

        engine.console = Console();
        game.vehiclePool
          ..clear()
          ..addAll([for (final id in vehicleTypes.keys) Vehicle(id)]);
        for (final person in game.squad) {
          person.preferredCarId = null;
        }
        final beforeVehicleInspection = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 59019);
        final vehicleRolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 59019);
        await sourceFlow(setVehicles, () async {
          for (var index = 0; index < game.vehiclePool.length; index++) {
            final lower = String.fromCharCode('a'.codeUnitAt(0) + index);
            for (final key in [lower, lower.toUpperCase()]) {
              final action = engine.console.actions.singleWhere(
                (a) => a.key == key,
              );
              expect(choiceVehicle(action), same(game.vehiclePool[index]));
            }
          }
          final visibleArt = tester
              .widgetList<CatalogueIllustration>(
                find.byType(CatalogueIllustration),
              )
              .map((widget) => _painting(widget.art))
              .toSet();
          for (final id in vehicleTypes.keys) {
            expect(visibleArt, contains(_painting(vehicleArtwork(id)!)));
          }
          final first = engine.console.actions.singleWhere((a) => a.key == 'a');
          final firstButton = find.byKey(
            ValueKey('direct-action:${first.y}:${first.x}:${first.key}'),
          );
          await tester.ensureVisible(firstButton);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(firstButton).height,
            lessThanOrEqualTo(160 * scale),
            reason:
                'Vehicle art must leave readable label width at $name size.',
          );
          await sourceCapture('$name-source-vehicle-assignments');
          expect(jsonEncode(game.gameState.toJson()), beforeVehicleInspection);
          await sourceAction('Enter');
        });
        expect(jsonEncode(game.gameState.toJson()), beforeVehicleInspection);
        expect(List.generate(12, (_) => lcsRandom(100000)), vehicleRolls);
      }
      journalReadingScale.value = 1;
    },
  );
}
