import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/newencounter.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  test(
    'encounter generation preserves pre-extraction seeded outcomes',
    () async {
      final fixture = await File('test/saves/felix_1_0.json').readAsString();
      final results = <String, Object>{};
      for (final type in SiteType.values) {
        for (final scenario in ['normal', 'security', 'alarm', 'ccs']) {
          game.gameState = decodeSaveContents(fixture).gameState!;
          game.mode = GameMode.base;
          final site = game.sites.first;
          site.type = type;
          site.controller = scenario == 'ccs'
              ? SiteController.ccs
              : SiteController.unaligned;
          game.activeSite = site;
          game.postAlarmTimer = scenario == 'alarm' ? 100 : 0;
          game.siteAlarm = scenario == 'alarm';
          reseedRNG(seed: 90231);
          prepareEncounter(type, scenario == 'security');
          results['${type.name}:$scenario'] = {
            'people': game.encounter.map((p) => p.type.id).toList(),
            'attributes': game.encounter
                .map((p) => p.rawAttributes.map((a, n) => MapEntry(a.name, n)))
                .toList(),
            'next': List.generate(10, (_) => lcsRandom(100000)),
          };
        }
      }
      final baseline = File('test/location_encounter_baseline.json');
      expect(results, jsonDecode(await baseline.readAsString()));
    },
  );
}
