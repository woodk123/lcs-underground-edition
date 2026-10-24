import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo_type.dart';
import 'package:lcs_new_age/items/armor_upgrade.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/flag_type.dart';
import 'package:lcs_new_age/items/item_type.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/saveload/load_cpc_images.dart';
import 'package:lcs_new_age/saveload/load_xml_data.dart';
import 'package:lcs_new_age/saveload/required_asset.dart';
import 'package:lcs_new_age/sitemode/shop.dart';
import 'package:lcs_new_age/sitemode/sitemap_from_tabscript.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

class _TransferBundle extends CachingAssetBundle {
  _TransferBundle({
    this.data = const {},
    this.failures = const {},
    this.fromDisk = false,
    Object? error,
    this.onRead,
  }) : error =
           error ??
           FlutterError(
             'Unable to load asset: flags.xml. net::ERR_CONNECTION_TIMED_OUT',
           );

  final Map<String, List<int>> data;
  final Map<String, int> failures;
  final bool fromDisk;
  final Object error;
  final void Function(String key, int attempt)? onRead;
  final reads = <String, int>{};
  final evictions = <String>[];
  final failureStack = StackTrace.fromString('injected asset transfer stack');

  @override
  Future<ByteData> load(String key) async {
    final attempt = reads.update(key, (value) => value + 1, ifAbsent: () => 1);
    onRead?.call(key, attempt);
    if (attempt <= (failures[key] ?? 0)) {
      Error.throwWithStackTrace(error, failureStack);
    }
    final bytes =
        data[key] ??
        (fromDisk
            ? await File(key).readAsBytes()
            : throw StateError('Unexpected asset $key'));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  @override
  void evict(String key) {
    evictions.add(key);
    super.evict(key);
  }
}

void _clearDataTables() {
  itemTypes.clear();
  ammoTypes.clear();
  armorUpgrades.clear();
  clothingTypes.clear();
  creatureTypes.clear();
  flagTypes.clear();
  lootTypes.clear();
  weaponTypes.clear();
  vehicleTypes.clear();
  shopTypes.clear();
  sitemaps.clear();
}

Object _dataTablesAndGraphics() => jsonDecode(
  jsonEncode({
    'items': {
      for (final entry in itemTypes.entries)
        entry.key: [
          entry.value.runtimeType.toString(),
          entry.value.name,
          entry.value.nameFuture,
          entry.value.fenceValue,
          entry.value.isMoney,
        ],
    },
    'creatures': {
      for (final entry in creatureTypes.entries) entry.key: entry.value.name,
    },
    'armor': {
      for (final entry in armorUpgrades.entries) entry.key: entry.value.name,
    },
    'flags': {
      for (final entry in flagTypes.entries)
        entry.key: [
          entry.value.asset,
          entry.value.category.name,
          entry.value.description,
          entry.value.buyable,
          entry.value.makeDifficulty,
          entry.value.makePrice,
        ],
    },
    'vehicles': {
      for (final entry in vehicleTypes.entries)
        entry.key: [
          entry.value.longName,
          entry.value.shortName,
          entry.value.yearStart,
          entry.value.yearAddRandomUpToCurrent,
          entry.value.yearAddRandom,
          entry.value.yearAdd,
          entry.value.driveBonus,
          entry.value.colors,
          entry.value.displayColor,
          entry.value.difficultyToFind,
          entry.value.juice,
          entry.value.extraHeat,
          entry.value.senseAlarmChance,
          entry.value.touchAlarmChance,
          entry.value.availableAtDealership,
          entry.value.price,
          entry.value.sleeperprice,
        ],
    },
    'shops': shopTypes.keys.toList(),
    'maps': [
      for (final map in sitemaps)
        [
          map.name,
          map.parent,
          [for (final command in map.commands) command.runtimeType.toString()],
        ],
    ],
    'largecap': bigletters,
    'newstops': newstops,
    'newspic': newspic,
    '5x5': letters5x5,
    '4x5': letters4x5,
    '3x5': letters3x5,
    '3x3': letters3x3,
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'assets/xml/flags.xml';

  for (final failures in [1, 2]) {
    test(
      'string read recovers after $failures failed transfer(s), evicting failed cached futures',
      () async {
        final bundle = _TransferBundle(
          data: {key: utf8.encode('<flags/>')},
          failures: {key: failures},
        );
        expect(await loadRequiredAssetString(key, bundle: bundle), '<flags/>');
        expect(bundle.reads[key], failures + 1);
        expect(bundle.evictions, List.filled(failures, key));
      },
    );
  }

  testWidgets('transfer retries wait 200ms then 400ms', (tester) async {
    final bundle = _TransferBundle(
      data: {key: utf8.encode('loaded')},
      failures: {key: 2},
    );
    final pending = loadRequiredAssetString(key, bundle: bundle);
    await tester.pump();
    expect(bundle.reads[key], 1);
    await tester.pump(const Duration(milliseconds: 199));
    expect(bundle.reads[key], 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(bundle.reads[key], 2);
    await tester.pump(const Duration(milliseconds: 399));
    expect(bundle.reads[key], 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(await pending, 'loaded');
    expect(bundle.reads[key], 3);
  });

  test(
    'successful reads preserve their cache and unrelated cached strings',
    () async {
      final data = {
        key: utf8.encode('loaded'),
        'other': utf8.encode('original'),
      };
      final bundle = _TransferBundle(data: data);
      expect(await bundle.loadString('other'), 'original');
      data['other'] = utf8.encode('changed');
      expect(await loadRequiredAssetString(key, bundle: bundle), 'loaded');
      expect(await loadRequiredAssetString(key, bundle: bundle), 'loaded');
      expect(bundle.reads[key], 1);
      expect(bundle.evictions, isEmpty);
      expect(await bundle.loadString('other'), 'original');
      expect(bundle.reads['other'], 1);
    },
  );

  test('recovery evicts only its failed key', () async {
    final data = {key: utf8.encode('loaded'), 'other': utf8.encode('original')};
    final bundle = _TransferBundle(data: data, failures: {key: 1});
    await bundle.loadString('other');
    data['other'] = utf8.encode('changed');
    expect(await loadRequiredAssetString(key, bundle: bundle), 'loaded');
    expect(await bundle.loadString('other'), 'original');
    expect(bundle.reads['other'], 1);
    expect(bundle.evictions, [key]);
  });

  test('binary data recovers before its parser runs', () async {
    final bytes = ByteData(16)
      ..setUint32(0, 1, Endian.little)
      ..setUint32(4, 1, Endian.little)
      ..setUint32(8, 1, Endian.little);
    bytes.buffer.asUint8List().setRange(12, 16, [65, 1, 2, 0]);
    final bundle = _TransferBundle(
      data: {'image.cpc': bytes.buffer.asUint8List()},
      failures: {'image.cpc': 2},
    );
    expect(await readCPCFile('image.cpc', bundle: bundle), [
      [
        [
          [65, 1, 2, 0],
        ],
      ],
    ]);
    expect(bundle.reads['image.cpc'], 3);
    expect(bundle.evictions, ['image.cpc', 'image.cpc']);
  });

  test('permanent read failure stops at three and preserves the final error and stack', () async {
    final failure = FlutterError(
      'Unable to load asset: $key. net::ERR_CONNECTION_TIMED_OUT',
    );
    final bundle = _TransferBundle(failures: {key: 99}, error: failure);
    try {
      await loadRequiredAssetString(key, bundle: bundle);
      fail('The permanent transfer failure must propagate.');
    } catch (error, stack) {
      expect(error, same(failure));
      expect(stack.toString(), contains('injected asset transfer stack'));
    }
    expect(bundle.reads[key], 3);
    expect(bundle.evictions, [key, key, key]);
  });

  test('malformed UTF-8 is not retried', () async {
    final bundle = _TransferBundle(
      data: {
        key: [0xc3, 0x28],
      },
    );
    await expectLater(
      loadRequiredAssetString(key, bundle: bundle),
      throwsFormatException,
    );
    expect(bundle.reads[key], 1);
    expect(bundle.evictions, isEmpty);
  });

  test(
    'CPC and cap-text parse failures do not retry successful transfers',
    () async {
      final bundle = _TransferBundle(
        data: {
          'broken.cpc': [0, 0, 0, 0],
          'broken.txt': utf8.encode('too short'),
        },
      );
      await expectLater(
        readCPCFile('broken.cpc', bundle: bundle),
        throwsRangeError,
      );
      await expectLater(
        readCapTextFile('broken.txt', 5, 5, bundle: bundle),
        throwsRangeError,
      );
      expect(bundle.reads, {'broken.cpc': 1, 'broken.txt': 1});
      expect(bundle.evictions, isEmpty);
    },
  );

  test(
    'asset recovery preserves campaign, current input and gameplay RNG',
    () async {
      final console = engine.console = Console();
      console.addAction('f', 'Current choice');
      final pending = console.getkey();
      final state = jsonEncode(game.gameState.toJson());
      final revision = console.revision.value;
      final completer = console.nextKeyEvent;
      final actions = List.of(console.actions);
      reseedRNG(seed: 4187);
      final expected = List.generate(10, (_) => lcsRandom(1000000));
      reseedRNG(seed: 4187);
      final bundle = _TransferBundle(
        data: {key: utf8.encode('loaded')},
        failures: {key: 2},
      );
      expect(await loadRequiredAssetString(key, bundle: bundle), 'loaded');
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(console.actions, orderedEquals(actions));
      expect(console.revision.value, revision);
      expect(console.nextKeyEvent, same(completer));
      expect(console.awaitingInput, true);
      expect(console.lastKey, isNull);
      expect(List.generate(10, (_) => lcsRandom(1000000)), expected);
      console.sendInput('Enter');
      await pending;
    },
  );

  test('complete XML, maps and graphics match baseline after individual read recovery without replay', () async {
    _clearDataTables();
    final baselineBundle = _TransferBundle(fromDisk: true);
    await loadXmlData(bundle: baselineBundle);
    await loadCpcGraphics(bundle: baselineBundle);
    final baseline = _dataTablesAndGraphics();
    final state = jsonEncode(game.gameState.toJson());
    _clearDataTables();
    final failures = {
      key: 2,
      'assets/maps/sitemaps.txt': 1,
      'assets/art/5x5caps.txt': 1,
      'assets/art/newspic.cpc': 1,
    };
    final recovering = _TransferBundle(
      fromDisk: true,
      failures: failures,
      onRead: (path, attempt) {
        if (path == key && attempt <= 2) {
          expect(
            flagTypes,
            isEmpty,
            reason: 'A rejected transfer has not reached the XML parser.',
          );
        }
      },
    );
    reseedRNG(seed: 412);
    final expected = List.generate(10, (_) => lcsRandom(1000000));
    reseedRNG(seed: 412);
    await loadXmlData(bundle: recovering);
    await loadCpcGraphics(bundle: recovering);
    expect(_dataTablesAndGraphics(), baseline);
    expect(jsonEncode(game.gameState.toJson()), state);
    expect(List.generate(10, (_) => lcsRandom(1000000)), expected);
    expect(recovering.reads.keys.toSet(), baselineBundle.reads.keys.toSet());
    for (final entry in baselineBundle.reads.entries) {
      expect(entry.value, 1);
      expect(
        recovering.reads[entry.key],
        1 + (failures[entry.key] ?? 0),
        reason: 'Do not replay earlier successful readers/parsers.',
      );
    }
    expect(sitemaps, isNotEmpty);
    expect(flagTypes, isNotEmpty);
    expect(vehicleTypes, isNotEmpty);
  });
}
