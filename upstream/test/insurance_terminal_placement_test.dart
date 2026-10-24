import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
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

  test('claims terminals use empty floor and preserve blocked fixtures', () {
    final x = MAPX >> 1;
    levelMap[x][3][0].wall = true;
    levelMap[x][4][0].door = true;
    levelMap[x][5][0].exit = true;
    levelMap[x][6][0].special = TileSpecial.insuranceCEO;
    levelMap[x][7][0].special = TileSpecial.insuranceFiles;
    levelMap[x][8][0].special = TileSpecial.stairsUp;
    final scatter = ConfigSiteSpecial('INSURANCE_CLAIMS_TERMINAL')
      ..configure('X', '0')
      ..configure('YSTART', '3')
      ..configure('YEND', '9')
      ..configure('Z', '0');
    scatter.build(); // FREQ defaults to 1: every eligible tile is selected.
    for (final y in [3, 4, 5]) {
      expect(levelMap[x][y][0].special, TileSpecial.none);
    }
    expect(levelMap[x][6][0].special, TileSpecial.insuranceCEO);
    expect(levelMap[x][7][0].special, TileSpecial.insuranceFiles);
    expect(levelMap[x][8][0].special, TileSpecial.stairsUp);
    expect(levelMap[x][9][0].special, TileSpecial.insuranceClaimsTerminal);

    scatter.configure('FREQ', '10');
    reseedRNG(seed: 391);
    for (var i = 0; i < 7; i++) {
      lcsRandom(10);
    }
    final nextRoll = lcsRandom(100000);
    reseedRNG(seed: 391);
    scatter.build();
    expect(
      lcsRandom(100000),
      nextRoll,
      reason: 'Rejected placements still consume their original roll.',
    );
  });

  test(
    'real insurance maps keep terminals accessible and unique rooms intact',
    () async {
      sitemaps.clear();
      addTearDown(sitemaps.clear);
      expect(await readConfigFile('assets/maps/sitemaps.txt'), isTrue);
      for (var seed = 0; seed < 30; seed++) {
        for (final tile in levelMap.all) {
          tile.flag = SITEBLOCK_BLOCK;
          tile.special = TileSpecial.none;
        }
        reseedRNG(seed: seed);
        buildSite('INSURANCE_OFFICES');
        final terminals = levelMap.all
            .where(
              (tile) => tile.special == TileSpecial.insuranceClaimsTerminal,
            )
            .toList();
        expect(terminals, isNotEmpty, reason: 'seed $seed');
        for (final tile in terminals) {
          expect(
            tile.wall || tile.door || tile.exit,
            isFalse,
            reason: 'seed $seed at ${tile.x},${tile.y},${tile.z}',
          );
        }
        for (final special in [
          TileSpecial.insuranceFiles,
          TileSpecial.insuranceCEO,
        ]) {
          expect(
            levelMap.all.where((tile) => tile.special == special),
            hasLength(1),
            reason: '$special must survive terminal scattering (seed $seed)',
          );
        }
      }
    },
  );
}
