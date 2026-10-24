import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemap_from_dame.dart';
import 'package:lcs_new_age/sitemode/sitemap_from_tabscript.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
  });

  test(
    'all scattered fixtures reject walls and room fixtures reject doors',
    () {
      final x = MAPX >> 1;
      for (final special in TileSpecial.values.where(
        (s) => s != TileSpecial.none,
      )) {
        levelMap[x][3][0]
          ..wall = true
          ..special = TileSpecial.none;
        levelMap[x][4][0]
          ..door = true
          ..special = TileSpecial.none;
        levelMap[x][5][0].special = TileSpecial.none;
        final scatter = ConfigSiteSpecial('INSURANCE_CLAIMS_TERMINAL')
          ..special = special
          ..configure('X', '0')
          ..configure('YSTART', '3')
          ..configure('YEND', '5')
          ..configure('Z', '0');
        scatter.build();
        expect(
          levelMap[x][3][0].special,
          TileSpecial.none,
          reason: special.name,
        );
        final sign = [
          TileSpecial.signOne,
          TileSpecial.signTwo,
          TileSpecial.signThree,
        ].contains(special);
        expect(
          levelMap[x][4][0].special,
          sign ? special : TileSpecial.none,
          reason: special.name,
        );
        expect(levelMap[x][5][0].special, special, reason: special.name);
      }
      // Internet cafes deliberately replace some inherited cafe tables.
      levelMap[x][5][0].special = TileSpecial.table;
      (ConfigSiteSpecial('CAFE_COMPUTER')
            ..configure('X', '0')
            ..configure('Y', '5')
            ..configure('Z', '0'))
          .build();
      expect(levelMap[x][5][0].special, TileSpecial.computer);
    },
  );

  test('authored procedural maps never put fixtures inside walls', () async {
    sitemaps.clear();
    addTearDown(sitemaps.clear);
    await readConfigFile('assets/maps/sitemaps.txt');
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    final failures = <String, int>{};
    for (final map in sitemaps) {
      for (var seed = 0; seed < 30; seed++) {
        for (final tile in levelMap.all) {
          tile.flag = SITEBLOCK_BLOCK;
          tile.special = TileSpecial.none;
        }
        reseedRNG(seed: seed);
        map.build();
        for (final tile in levelMap.all) {
          if (tile.wall && tile.special != TileSpecial.none) {
            final key = '${map.name}: ${tile.special.name}';
            failures.update(key, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.toString());
  });

  test(
    'random prison stairs connect matching open tiles on all three floors',
    () async {
      sitemaps.clear();
      addTearDown(sitemaps.clear);
      await readConfigFile('assets/maps/sitemaps.txt');
      for (var seed = 0; seed < 30; seed++) {
        for (final tile in levelMap.all) {
          tile.flag = SITEBLOCK_BLOCK;
          tile.special = TileSpecial.none;
        }
        reseedRNG(seed: seed);
        buildSite('GOVERNMENT_PRISON');
        final up = levelMap.all
            .where((t) => t.special == TileSpecial.stairsUp)
            .toList();
        final down = levelMap.all
            .where((t) => t.special == TileSpecial.stairsDown)
            .toList();
        expect(up, hasLength(2), reason: 'seed $seed');
        expect(down, hasLength(2), reason: 'seed $seed');
        for (final tile in up) {
          final destination = levelMap[tile.x][tile.y][tile.z + 1];
          expect(
            tile.blocked || destination.blocked,
            isFalse,
            reason: 'seed $seed',
          );
          expect(destination.special, TileSpecial.stairsDown);
        }
      }
    },
  );

  test('legacy special placement leaves an all-blocked map alone', () {
    for (final tile in levelMap.all) {
      tile.wall = true;
    }
    addOldMapSpecials(Site(SiteType.nuclearPlant));
    expect(levelMap.all.every((t) => t.special == TileSpecial.none), isTrue);
    final floor = levelMap[10][10][0]..wall = false;
    addOldMapSpecials(Site(SiteType.nuclearPlant));
    expect(floor.special, TileSpecial.nuclearControlRoom);
    addOldMapSpecials(Site(SiteType.ceoHouse));
    expect(
      floor.special,
      TileSpecial.nuclearControlRoom,
      reason:
          'No eligible floor remains; do not overwrite the fixture or a wall.',
    );
    expect(
      levelMap.all
          .where((t) => t.wall)
          .every((t) => t.special == TileSpecial.none),
      isTrue,
    );
  });

  test('bundled CSV maps have no fixtures in walls', () {
    final specials = Directory('assets/maps')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_Specials.csv'))
        .toList();
    expect(specials, isNotEmpty);
    for (final file in specials) {
      for (final tile in levelMap.all) {
        tile.flag = 0;
        tile.special = TileSpecial.none;
      }
      final terrain = File(
        file.path.replaceFirst('_Specials.csv', '_Tiles.csv'),
      );
      applyMapCsv(terrain.readAsStringSync(), 0, readMapCBTiles);
      applyMapCsv(file.readAsStringSync(), 0, readMapCBSpecials);
      expect(
        levelMap.all.where((t) => t.wall && t.special != TileSpecial.none),
        isEmpty,
        reason: file.path,
      );
    }
  });
}
