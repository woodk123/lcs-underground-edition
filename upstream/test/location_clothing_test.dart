import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/location_clothing.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/stealth.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  late String fixture;
  late Site destination;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.laws.updateAll((_, _) => DeepAlignment.moderate);
    destination = game.sites.first
      ..type = SiteType.insuranceOffice
      ..controller = SiteController.unaligned
      ..highSecurity = 0;
  });

  DisguiseQuality fit(String id, {bool restricted = true}) => locationClothing(
    destination,
    restricted: restricted,
  ).singleWhere((outfit) => outfit.type.idName == id).quality;

  test(
    'insurance distinguishes visitors from a formal private-area disguise',
    () {
      expect(
        fit('CLOTHING_CLOTHES', restricted: false),
        DisguiseQuality.inconspicuous,
      );
      expect(fit('CLOTHING_CLOTHES'), DisguiseQuality.trespassing);
      expect(fit('CLOTHING_CHEAPSUIT'), DisguiseQuality.inconspicuous);
      expect(fit('CLOTHING_CHEAPDRESS'), DisguiseQuality.inconspicuous);
      expect(fit('CLOTHING_POLICEUNIFORM'), DisguiseQuality.authorityFigure);
      expect(fit('CLOTHING_LABCOAT'), DisguiseQuality.trespassing);
    },
  );

  test('lab security uniforms change rating at high security', () {
    destination.type = SiteType.cosmeticsLab;
    for (final id in [
      'CLOTHING_LABCOAT',
      'CLOTHING_SCRUBS',
      'CLOTHING_OVERALLS',
    ]) {
      expect(fit(id), DisguiseQuality.inconspicuous);
    }
    expect(fit('CLOTHING_SECURITYUNIFORM'), DisguiseQuality.authorityFigure);
    destination.highSecurity = 100;
    expect(fit('CLOTHING_SECURITYUNIFORM'), DisguiseQuality.inconspicuous);
  });

  test(
    'industrial work clothes apply throughout the site, with a security exception',
    () {
      destination.type = SiteType.dirtyIndustry;
      for (final restricted in [false, true]) {
        expect(
          fit('CLOTHING_WORKCLOTHES', restricted: restricted),
          DisguiseQuality.inconspicuous,
        );
        expect(
          fit('CLOTHING_CLOTHES', restricted: restricted),
          DisguiseQuality.trespassing,
        );
        expect(
          fit('CLOTHING_SECURITYUNIFORM', restricted: restricted),
          DisguiseQuality.authorityFigure,
        );
      }
      destination.highSecurity = 100;
      expect(fit('CLOTHING_SECURITYUNIFORM'), DisguiseQuality.inconspicuous);
    },
  );

  test(
    'private apartments offer no normal outfit and authority is not normal',
    () {
      destination.type = SiteType.apartment;
      final clothes = locationClothing(destination, restricted: true);
      expect(clothingFitSummary(clothes), 'No listed outfit blends in here.');
      expect(fit('CLOTHING_POLICEUNIFORM'), DisguiseQuality.authorityFigure);
      expect(fit('CLOTHING_CHEAPSUIT'), DisguiseQuality.trespassing);
    },
  );

  test('prison outfits follow current dystopian prison law', () {
    destination.type = SiteType.prison;
    expect(fit('CLOTHING_PRISONGUARD'), DisguiseQuality.inconspicuous);
    expect(fit('CLOTHING_LABCOAT'), DisguiseQuality.trespassing);
    for (final law in [
      Law.prisons,
      Law.privacy,
      Law.military,
      Law.policeReform,
    ]) {
      game.laws[law] = DeepAlignment.archConservative;
    }
    expect(fit('CLOTHING_LABCOAT'), DisguiseQuality.inconspicuous);
    expect(fit('CLOTHING_PRISONGUARD'), DisguiseQuality.authorityFigure);
    expect(fit('CLOTHING_SCRUBS'), DisguiseQuality.inconspicuous);
  });

  test('site control and siege context apply to the destination', () {
    destination.type = SiteType.barAndGrill;
    expect(fit('CLOTHING_CAMOSUIT'), DisguiseQuality.trespassing);
    destination.controller = SiteController.ccs;
    expect(fit('CLOTHING_CAMOSUIT'), DisguiseQuality.inconspicuous);
    destination.controller = SiteController.unaligned;
    destination.siege.activeSiegeType = SiegeType.cia;
    expect(fit('CLOTHING_CHEAPSUIT'), DisguiseQuality.trespassing);
    expect(fit('CLOTHING_BLACKSUIT'), DisguiseQuality.inconspicuous);
    destination.controller = SiteController.lcs;
    expect(fit('CLOTHING_CHEAPSUIT'), DisguiseQuality.inconspicuous);
  });

  test('condition and added visible armor still affect the live rule', () {
    final outfit = Clothing('CLOTHING_CHEAPSUIT');
    DisguiseQuality current() => clothingDisguiseQuality(
      outfit,
      site: destination,
      restricted: true,
      deathSquads: false,
      dystopianPrison: false,
    );
    expect(current(), DisguiseQuality.inconspicuous);
    outfit.quality = outfit.type.qualityLevels;
    expect(current(), DisguiseQuality.unusual);
    outfit.damaged = true;
    expect(current(), DisguiseQuality.disturbing);
    outfit.quality = 1;
    outfit.damaged = false;
    outfit.armorId = 'ARMOR_MILITARY';
    expect(outfit.armor?.visible, isTrue);
    expect(current(), DisguiseQuality.alarming);
  });

  test(
    'all guides preserve the campaign, active operation, outfit and RNG',
    () {
      game.activeSite = game.sites.firstWhere(
        (site) => site.type == SiteType.armyBase,
      );
      game.locx = 35;
      game.locy = 1;
      game.locz = 0;
      currentTile.restricted = true;
      final actor = game.pool.first;
      final outfit = actor.equippedClothing;
      final before = jsonEncode(game.gameState.toJson());
      final tileBefore = currentTile.flag;
      reseedRNG(seed: 853427);
      final expected = List.generate(20, (_) => lcsRandom(100000));
      reseedRNG(seed: 853427);
      for (final site in game.sites) {
        for (final restricted in [false, true]) {
          final clothes = locationClothing(site, restricted: restricted);
          expect(clothes, isNotEmpty);
          expect(
            clothes.any((outfit) => outfit.type.idName == 'CLOTHING_NONE'),
            isFalse,
          );
          clothingFitSummary(clothes);
        }
      }
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(currentTile.flag, tileBefore);
      expect(actor.equippedClothing, same(outfit));
      expect(List.generate(20, (_) => lcsRandom(100000)), expected);
    },
  );
}
