import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/medical_support.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/recovery_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature patient;
  late Site site;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    patient = game.pool.first;
    site = game.sites.first..controller = SiteController.lcs;
    for (final person in game.pool) {
      person.location = site;
      person.alive = true;
      person.hidingDaysLeft = 0;
      person.sleeperAgent = false;
      person.rawSkill[Skill.firstAid] = 0;
    }
    patient.body = HumanoidBody();
    patient.blood = patient.maxBlood - 20;
  });

  test(
    'automatic support includes self and takes highest, without stacking',
    () {
      patient.rawSkill[Skill.firstAid] = 3;
      expect(medicalSupportAt(site, game.pool), 3);
      final helper = game.pool[1]..rawSkill[Skill.firstAid] = 8;
      expect(medicalSupportAt(site, game.pool), 8);
      expect(dailyRecoveryHelp(patient).first, contains('+4 blood/day'));
      expect(dailyRecoveryHelp(patient).join(), contains('1 to 50 XP'));
      expect(
        dailyRecoveryHelp(patient).join(),
        contains('not just the strongest medic'),
      );
      helper.hidingDaysLeft = 1;
      expect(medicalSupportAt(site, game.pool), 3);
      helper.hidingDaysLeft = 0;
      helper.sleeperAgent = true;
      expect(medicalSupportAt(site, game.pool), 3);
      helper.sleeperAgent = false;
      helper.alive = false;
      expect(medicalSupportAt(site, game.pool), 3);
      helper.alive = true;
      helper.location = game.sites[1];
      expect(medicalSupportAt(site, game.pool), 3);
    },
  );

  test('facility floors and starvation match daily care', () {
    site.controller = SiteController.unaligned;
    expect(medicalSupportAt(site, game.pool), 6);
    site.type = SiteType.universityHospital;
    expect(medicalSupportAt(site, game.pool), 16);
    patient.rawSkill[Skill.firstAid] = 18;
    expect(medicalSupportAt(site, game.pool), 18);
    site.siege.activeSiegeType = SiegeType.police;
    site.compound.rations = 0;
    expect(medicalSupportAt(site, game.pool), 16);
    site.type = SiteType.warehouse;
    site.controller = SiteController.lcs;
    expect(medicalSupportAt(site, game.pool), 0);
    expect(dailyRecoveryHelp(patient).first, contains('+2 blood/day'));
  });

  test('ceilings, final blood point, absent site and deceased records', () {
    patient.rawSkill[Skill.firstAid] = 9;
    patient.blood = patient.maxBlood - 1;
    expect(dailyRecoveryHelp(patient).first, contains('+1 blood/day'));
    patient.blood = patient.maxBlood - 20;
    (patient.body as HumanoidBody).puncturedHeart = true;
    // Severity 3 caps medical recovery at 60%; above it only natural recovery remains.
    expect(dailyRecoveryHelp(patient).first, contains('+1 blood/day'));
    expect(dailyRecoveryHelp(patient).join(), contains('treatment severity 3'));
    patient.location = null;
    expect(
      dailyRecoveryHelp(patient).join(),
      contains('No site: no daily medical care'),
    );
    patient.alive = false;
    expect(dailyRecoveryHelp(patient), isEmpty);
  });

  test('explaining support and ceilings preserves campaign and RNG', () {
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 20261024);
    final expected = List.generate(5, (_) => lcsRandom(10000));
    reseedRNG(seed: 20261024);
    dailyRecoveryHelp(patient);
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(List.generate(5, (_) => lcsRandom(10000)), expected);
  });
}
